export rl_unplugged_atari_dataset

using Base.Threads
using Printf:@sprintf
using Base.Iterators
using TFRecord
using ImageCore
using PNGFiles

# TODO: Improve naming conventions and make the package more uniform.
"""
    RLTransition

Represents an RLTransition. It can also be used to represent a batch by adding another dimension.

The constructor decodes the incoming `TFRecord.Example` to be ready to use.

Fields:
- `state`
- `action`
- `reward`
- `terminal`
- `next_state`
- `next_action`
- `episode_id`
- `episode_return`
"""
struct RLTransition
    state
    action
    reward
    terminal
    next_state
    next_action
    episode_id
    episode_return
end

function batch(template::RLTransition, src::RLTransition, i::Int)
    for fn in fieldnames(RLTransition)
        xs = getfield(template, fn)
        x = getfield(src, fn)
        selectdim(xs, ndims(xs), i) .= x
    end
    return template
end

function decode_frame(bytes)
    bytes |> IOBuffer |> PNGFiles.load |> channelview |> rawview
end

function decode_state(bytes)
    PermutedDimsArray(StackedView((decode_frame(x) for x in bytes)...), (2,3,1))
end

function RLTransition(example::TFRecord.Example)
    f = example.features.feature
    s = decode_state(f["o_t"].bytes_list.value)
    s′ = decode_state(f["o_tp1"].bytes_list.value)
    a = f["a_t"].int64_list.value[]
    a′ = f["a_tp1"].int64_list.value[]
    r = f["r_t"].float_list.value[]
    t = f["d_t"].float_list.value[] != 1.0
    episode_id = f["episode_id"].int64_list.value[]
    episode_return = f["episode_return"].float_list.value[]
    RLTransition(s, a, r, t, s′, a′, episode_id, episode_return)
end
"""
    rl_unplugged_atari_dataset(game::String, run::Int, shards::Vector{Int}; (optional_args))

Returns a buffered `Channel` of `RLTransition` batches which supports multi threading.

### Arguments and optional_args:

- `game::String`, The name of the env.
- `run::Int`, The run number. Can be in the range 1:5.
- `shards::Vector{Int}` The shards that are to be loaded.
optional_args:
- `shuffle_buffer_size=10_000`, This is the size of the shuffle_buffer used in loading RLTransitions.
- `tf_reader_bufsize=1*1024*1024`, The size of the buffer `bufsize` that is used internally in `TFRecord.read`.
- `tf_reader_sz=10_000`, The size of the `Channel`, `channel_size` that is returned by `TFRecord.read`.
- `batch_size=256`, The size of the batches that are returned by the Channel that is finally returned.
- `n_preallocations`, The size of the buffer in the `Channel` that is returned.

!!! note

    To enable reading records from multiple files concurrently, remember to set the number of threads correctly (See [JULIA_NUM_THREADS](https://docs.julialang.org/en/v1/manual/environment-variables/#JULIA_NUM_THREADS)).
"""
function rl_unplugged_atari_dataset(
    game::String,
    run::Int,
    shards::Vector{Int};
    shuffle_buffer_size = 10_000,
    tf_reader_bufsize = 1*1024*1024,
    tf_reader_sz = 10_000,
    batch_size = 256,
    n_preallocations = nthreads() * 12
)
    n = nthreads()

    @info "Loading the shards $shards in $run run of $game with $n threads"

    folders = [
        @datadep_str "rl-unplugged-atari-$(titlecase(game))-$run-$shard"
        for shard in shards
    ]
    
    ch_files = Channel{String}(length(folders)) do ch
        for folder in cycle(folders)
            file = folder * "/$(readdir(folder)[1])"
            put!(ch, file)
        end
    end
    
    shuffled_files = buffered_shuffle(ch_files, length(folders))
    
    ch_src = Channel{RLTransition}(n * tf_reader_sz) do ch
        for fs in partition(shuffled_files, n)
            Threads.foreach(
                TFRecord.read(
                    fs;
                    compression=:gzip,
                    bufsize=tf_reader_bufsize,
                    channel_size=tf_reader_sz,
                );
                schedule=Threads.StaticSchedule()
            ) do x
                put!(ch, RLTransition(x))
            end
        end
    end
    
    transitions = buffered_shuffle(
        ch_src,
        shuffle_buffer_size
    )
    
    buffer_template = RLTransition(
        Array{UInt8, 4}(undef, 84, 84, 4, batch_size),
        Array{Int, 1}(undef, batch_size),
        Array{Float32, 1}(undef, batch_size),
        Array{Bool, 1}(undef, batch_size),
        Array{UInt8, 4}(undef, 84, 84, 4, batch_size),
        Array{Int, 1}(undef, batch_size),
        Array{Int, 1}(undef, batch_size),
        Array{Float32, 1}(undef, batch_size),
    )

    taskref = Ref{Task}()

    res = Channel{RLTransition}(n_preallocations; taskref=taskref, spawn=true) do ch
        Threads.@threads for i in 1:batch_size
            put!(ch, deepcopy(batch(buffer_template, popfirst!(transitions), i)))
        end
    end

    bind(ch_src, taskref[])
    bind(ch_files, taskref[])
    res
end