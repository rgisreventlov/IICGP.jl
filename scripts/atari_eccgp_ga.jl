using ArcadeLearningEnvironment
using ArgParse
using Cambrian
using CartesianGeneticProgramming
using Dates
using IICGP
using Random

import Cambrian.mutate # function extension


s = ArgParseSettings()
@add_arg_table! s begin
    "--cfg"
    help = "configuration script"
    default = "cfg/dualcgpga_atari_pooling.yaml"
    "--game"
    help = "game rom name"
    default = "gravitar"
    "--seed"
    help = "random seed for evolution"
    arg_type = Int
    default = 0
    "--out"
    help = "output directory"
    arg_type = String
    default = dirname(@__DIR__)
    "--ind"
    help = "individual for evaluation"
    arg_type = String
    default = ""
end

args = parse_args(ARGS, s)
const cfgpath = args["cfg"]
const rom = args["game"]
const seed = args["seed"]
const resdir = args["out"]
mcfg, ecfg, ccfg, reducer, bootstrap = IICGP.dualcgp_config(cfgpath, rom)
const max_frames = mcfg["max_frames"]
const stickiness = mcfg["stickiness"]
const grayscale = mcfg["grayscale"]
const downscale = mcfg["downscale"]
const logid = mcfg["id"]

function play_atari(
    ind::ECCGP,
    seed::Int64,
    lck::ReentrantLock;
    rom=rom,
    max_frames=max_frames,
    grayscale=grayscale,
    downscale=downscale,
    stickiness=stickiness
)
    # Random.seed!(seed)
    mt = MersenneTwister(seed)
    game = Game(rom, seed, lck=lck)
    IICGP.reset!(ind.reducer) # zero buffers
    reward = 0.0
    frames = 0
    prev_action = Int32(0)
    while ~game_over(game.ale)
        if rand(mt) > stickiness || frames == 0
            s = get_state(game, grayscale, downscale)
            output = IICGP.process(ind, s)
            action = game.actions[argmax(output)]
        else
            action = prev_action
        end
        reward += act(game.ale, action)
        frames += 1
        prev_action = action
        if frames > max_frames
            break
        end
    end
    close!(game)
    [reward, frames]
end

"""
    mutate(ind::ECCGP, ind_type::String)

Mutate function for an EC-CGP (encoder-controller pair). Mutate both the
encoder and the controller so that child pair is structurally different.
"""
function mutate(ind::ECCGP)
    ind.encoder = goldman_mutate(ecfg, ind.encoder, init_function=IPCGPInd)
    ind.controller = goldman_mutate(ecfg, ind.controller)
    ind
end

lck = ReentrantLock()
fit(ind::ECCGP, seed::Int64) = play_atari(ind, seed, lck)

evo = IICGP.DualCGPGAEvo(mcfg, ecfg, ccfg, fit, logid, resdir)

init_backup(logid, resdir, cfgpath)
run!(evo)
