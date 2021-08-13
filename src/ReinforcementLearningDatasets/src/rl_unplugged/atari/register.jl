import Printf.@sprintf

# 9 tuning games.
const TUNING_SUITE = [
    "BeamRider",
    "DemonAttack",
    "DoubleDunk",
    "IceHockey",
    "MsPacman",
    "Pooyan",
    "RoadRunner",
    "Robotank",
    "Zaxxon",
]

# 36 testing games.
const TESTING_SUITE = [
    "Alien",
    "Amidar",
    "Assault",
    "Asterix",
    "Atlantis",
    "BankHeist",
    "BattleZone",
    "Boxing",
    "Breakout",
    "Carnival",
    "Centipede",
    "ChopperCommand",
    "CrazyClimber",
    "Enduro",
    "FishingDerby",
    "Freeway",
    "Frostbite",
    "Gopher",
    "Gravitar",
    "Hero",
    "Jamesbond",
    "Kangaroo",
    "Krull",
    "KungFuMaster",
    "NameThisGame",
    "Phoenix",
    "Pong",
    "Qbert",
    "Riverraid",
    "Seaquest",
    "SpaceInvaders",
    "StarGunner",
    "TimePilot",
    "UpNDown",
    "VideoPinball",
    "WizardOfWor",
    "YarsRevenge",
]

# Total of 45 games.
const ALL = cat(TUNING_SUITE, TESTING_SUITE, dims=1)

function fetch_rl_unplugged_atari(src, dest)
    try run(`which gsutil`) catch x throw("gsutil not found, install gsutil to proceed further") end
    
    run(`gsutil -m cp $src $dest`)
    return dest
end

num_shards = 100

function rl_unplugged_atari_init()
    for game in ALL
        for run in 1:5
            for index in 0:99
                register(
                    DataDep(
                        "rl-unplugged-atari-$game-$run-$index",
                        """
                        Dataset: RL Unplugged atari
                        Credits: https://arxiv.org/abs/2006.13888
                        Url: https://github.com/deepmind/deepmind-research/tree/master/rl_unplugged
                        Authors: Caglar Gulcehre, Ziyu Wang, Alexander Novikov, Tom Le Paine,
                        Sergio Gómez Colmenarejo, Konrad Zolna, Rishabh Agarwal,
                        Josh Merel, Daniel Mankowitz, Cosmin Paduraru, Gabriel
                        Dulac-Arnold, Jerry Li, Mohammad Norouzi, Matt Hoffman,
                        Ofir Nachum, George Tucker, Nicolas Heess, Nando deFreitas
                        Year: 2020

                        Data accompanying [RL Unplugged: Benchmarks for Offline Reinforcement Learning].
                        The dataset is generated by running an online DQN agent and recording transitions 
                        from its replay during training with sticky actions Machado et al., 2018. As stated
                        in Agarwal et al., 2020, for each game we use data from five runs with 50 million 
                        transitions each. States in each transition include stacks of four frames to be able
                        to do frame-stacking with our baselines. We release datasets for 46 Atari games. 
                        For details on how the dataset was generated, please refer to the paper.
                        Atari is a standard RL benchmark. We recommend you to try offline RL methods 
                        on Atari if you are interested in comparing your approach to other state of the 
                        art offline RL methods with discrete actions.
                        """,
                        "gs://rl_unplugged/atari/$game/"*@sprintf("run_%i-%05i-of-%05i", run, index, num_shards);
                        fetch_method = fetch_rl_unplugged_atari
                    )
                )
            end
        end
    end
end