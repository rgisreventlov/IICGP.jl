using ArcadeLearningEnvironment
using ArgParse
using Cambrian
using CartesianGeneticProgramming
using Dates
using IICGP
using Random
using UnicodePlots

import Cambrian.mutate

out(plt) = println(IOContext(stdout, :color=>true), plt)
default_resdir = joinpath(dirname(@__DIR__), "results")
default_cfgdir = joinpath(dirname(@__DIR__), "cfg")

function dict2namedtuple(d::Dict)
    (; (Symbol(k)=>v for (k, v) in d)...)
end

function print_usage(gen::Int64)
	out = read(`top -bn1 -p $(getpid())`, String)
	res = split(split(out,  "\n")[end-1])
	println("gen: ", gen, "   RES: ", res[6], "   %MEM: ", res[10],
			"   %CPU: ", res[9])
	parse(Float64, replace(res[10], "," => "."))
end

function append_ec_cfgs!(mcfg, ecfg, ccfg)
	mcfg["e_config"] = ecfg
	mcfg["c_config"] = ccfg
end

s = ArgParseSettings()
@add_arg_table! s begin
    "--cfg"
    help = "configuration script"
    default = joinpath(default_cfgdir, "eccgp_atari_ucea.yaml")
    "--game"
    help = "game rom name"
    default = "boxing"
    "--seed"
    help = "random seed"
    default = 0
    "--out"
    help = "output directory"
    arg_type = String
    default = default_resdir
end

args = parse_args(ARGS, s)
const cfg_path = args["cfg"]
const rom_name = args["game"]
#const seed = args["seed"]
const resdir = args["out"]
mcfg, ecfg, ccfg, reducer, bootstrap = IICGP.dualcgp_config(cfg_path, rom_name)
append_ec_cfgs!(mcfg, ecfg, ccfg) # Ugly fix for tracking e/c configs
mcfg = dict2namedtuple(mcfg)
const max_frames = mcfg.max_frames
const grayscale = mcfg.grayscale
const downscale = mcfg.downscale
const stickiness = mcfg.stickiness
const lck = ReentrantLock()

function atari_score(
	game::Game,
    encoder::CGPInd,
    reducer::Reducer,
    controller::CGPInd,
    seed::Int64;
    lck::ReentrantLock=lck,
    rom::String=rom_name,
    max_frames::Int64=max_frames,
    grayscale::Bool=grayscale,
    downscale::Bool=downscale,
    stickiness::Float64=stickiness
)
    Random.seed!(seed)
    mt = MersenneTwister(seed)
    #game = Game(rom, seed, lck=lck)
	IICGP.reset!(game)
    IICGP.reset!(reducer) # zero buffers
	s = get_state_buffer(game, grayscale)
	o = get_observation_buffer(game, grayscale, downscale)
    reward = 0.0
    frames = 0
    prev_action = Int32(0)
    while ~game_over(game.ale)
		if rand(mt) > stickiness || frames == 0
			get_state!(s, game, grayscale)
			get_observation!(o, s, game, grayscale, downscale)
            output = IICGP.process(encoder, reducer, controller, ccfg, o)
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
    #close!(game)
    reward, frames
end

# User-defined fitness function
function my_fitness(ind::UCInd, seed::Int64, game::Game)
    enco = IPCGPInd(ecfg, ind.e_chromosome)
    cont = CGPInd(ccfg, ind.c_chromosome)
    score, f = atari_score(game, enco, reducer, cont, seed)
	ind.reached_frames = f
    score
end

# User-defined mutation function
function mutate(ind::UCInd)
    e = IPCGPInd(ecfg, ind.e_chromosome)
    e_child = goldman_mutate(ecfg, e, init_function=IPCGPInd)
    c = CGPInd(ccfg, ind.c_chromosome)
    c_child = goldman_mutate(ccfg, c)
    UCInd(e_child.chromosome, c_child.chromosome)
end

# User-defined population initialization function
function random_init(indtype::Type, config::NamedTuple)
    [indtype(
        IPCGPInd(ecfg).chromosome,
        CGPInd(ccfg).chromosome
    ) for _ in 1:config.n_population]
end

# Initial population containing best constant action individuals
function cstind_init(indtype::Type, config::NamedTuple)
    # Create cst individuals
    cstinds = IICGP.get_cstind(indtype, rom_name, config, ecfg, ccfg, reducer)
    # Evaluate cst individuals and sort by 1st objective
	seed = 0
	game = Game(rom_name, seed)
    @inbounds for i in eachindex(cstinds)
		IICGP.reset!(game)
		push!(cstinds[i].fitnesses, my_fitness(cstinds[i], seed, game))
    end
	close!(game)
	for ind in cstinds
		ind.lifetime += min(config.n_population, length(cstinds))
	end
	sort!(cstinds, by=ind->mean_fitness(ind), rev = true)
    # Select best n_population individuals (fill lacking with random)
	if length(cstinds) > config.n_population
		cstinds =  cstinds[1:config.n_population]
	else
		push!(cstinds, [indtype(config, IPCGPInd(ecfg).chromosome,
			  CGPInd(ccfg).chromosome) for _ in 1:config.n_population-length(cstinds)]...)
	end
	@assert length(cstinds) == config.n_population
	cstinds
end

# Create evolution framework
e = UCEvo{UCInd}(mcfg, resdir, my_fitness, cstind_init, rom_name)
mem_usage = Vector{Float64}()

# Run experiment
init_backup(mcfg.id, resdir, cfg_path)
for i in 1:e.config.n_gen
    e.gen += 1
    if e.gen > 1
        populate(e)
    end
    evaluate(e)
	if (e.config.log_gen > 0) && (e.gen == 1 || mod(e.gen, e.config.log_gen) == 0)
    	log_gen(e)
    end
    generation(e)
	# Track memory usage
	mem = print_usage(i)
	push!(mem_usage, mem)
	out(lineplot(mem_usage, title = "%MEM"))
end

# Close games
for g in e.atari_games
	close!(g)
end
