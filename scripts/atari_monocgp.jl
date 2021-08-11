using ArcadeLearningEnvironment
using ArgParse
using Cambrian
using CartesianGeneticProgramming
using Dates
using IICGP
# using Distributed
import Random

# function extension
import Cambrian.mutate
import Cambrian.evaluate


s = ArgParseSettings()
@add_arg_table! s begin
    "--cfg"
    help = "configuration script"
    default = "cfg/test_mono.yaml"
    "--game"
    help = "game rom name"
    default = "assault"
    "--seed"
    help = "random seed for evolution"
    arg_type = Int
    default = 0
    "--ind"
    help = "individual for evaluation"
    arg_type = String
    default = ""
end
args = parse_args(ARGS, s)
const seed = args["seed"]
Random.seed!(seed)

main_cfg, cont_cfg, reducer, bootstrap = IICGP.monocgp_config(args["cfg"], args["game"])

const max_frames = main_cfg["max_frames"]
const stickiness = main_cfg["stickiness"]
const logid = cont_cfg.id

# TODO remove START
game = Game("assault", 0)
rgb0 = get_rgb(game)
# plt = implot(rgb0[1])
# display(plt)
close!(game)
# TODO remove END

function play_atari(
    reducer::Reducer,
    controller::CGPInd,
    lck::ReentrantLock;
    seed=seed,
    max_frames=max_frames,
    stickiness=stickiness
)
    println("-----------------------------------------------------") # TODO remove
    println("threadid   : ", Threads.threadid()) # TODO remove
    println("seed       : ", seed) # TODO remove
    Random.seed!(seed)
    println("seed       : ", seed) # TODO remove
    game = Game(args["game"], seed, lck=lck)
    println("seed       : ", seed) # TODO remove
    rgb = get_rgb(game)
    println("equal rgb0 : ", rgb == rgb0) # TODO remove
    println("stickiness : ", stickiness) # TODO remove
    println("-----------------------------------------------------") # TODO remove
    reward = 0.0
    frames = 0
    prev_action = 0
    while ~game_over(game.ale)
        if rand() > stickiness || frames == 0
            output = IICGP.process(reducer, controller, get_rgb(game))
            action = game.actions[argmax(output)]
        else
            action = prev_action
        end
        reward += act(game.ale, action)
        frames += 1
        if frames > max_frames
            break
        end
    end
    close!(game)
    [reward]
end

if length(args["ind"]) > 0
    ind = CGPInd(cfg, read(args["ind"], String))
    ftn = fitness(ind, inps, outs)
    println("Fitness: ", ftn)
else
    mutate(ind::CGPInd) = goldman_mutate(cont_cfg, ind)
    lck = ReentrantLock()
    fit(controller::CGPInd) = play_atari(reducer, controller, lck)
    evaluate(e::CGPEvolution) = IICGP.fitness_evaluate(e, e.fitness)
    e = CartesianGeneticProgramming.CGPEvolution(cont_cfg, fit)
    init_backup(logid, args["cfg"])
    run!(e)
    # fetch_backup()
end
