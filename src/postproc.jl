export process_results, process_nsga2_results, process_ucea_results

using DataFrames
using Plots
using ImageFiltering
using OffsetArrays
using BenchmarkTools
using Statistics
using CSV
using TimerOutputs

BASELINES = Dict(
    "assault"=>Dict("MTCGP"=>(890.4, 255), "A3C LSTM"=>14497.9),
    "asteroids"=>Dict("MTCGP"=>(9412,1818)),
    "boxing"=>Dict("MTCGP"=>(38.4,4), "Dueling"=>77.3),
    "breakout"=>Dict("MTCGP"=>(13.2,2), "A3C LSTM"=>766.8),
    "defender"=>Dict("MTCGP"=>(993010,2739)),
    "freeway"=>Dict("MTCGP"=>(28.2,0), "HyperNEAT"=>29),
    "frostbite"=>Dict("MTCGP"=>(782,795), "TPG"=>8144.4),
    "gravitar"=>Dict("MTCGP"=>(2350,50)),
    "private_eye"=>Dict("MTCGP"=>(12702.2,4337), "TPG"=>15028.3),
    "pong"=>Dict("MTCGP"=>(20,0)),
    "riverraid"=>Dict("MTCGP"=>(2914,90), "Prioritized"=>18184.4),
    "solaris"=>Dict("MTCGP"=>(8324,2250)),
    "space_invaders"=>Dict("MTCGP"=>(1001,25), "A3C LSTM"=>23846)
)

gamename_from_romname(rn::String) = titlecase(replace(rn, "_"=>" "))

"""
    function time_monocgp_ms(
        reducer::Reducer,
        cont::CGPInd,
        game_name::String
    )

Time forward pass of complete architecture.
Return time in ms.
"""
function time_monocgp_ms(
    reducer::Reducer,
    cont::CGPInd,
    game_name::String,
    grayscale::Bool,
    downscale::Bool
)
    # Generate input
    g = Game(game_name, 0)
    inp = get_state(g, grayscale, downscale)
    close!(g)
    # Pre-compile
    process(reducer, cont, inp)
    n_iter = 1000
    # Time
    redu_time = 0.0
    flat_time = 0.0
    cont_time = 0.0
    for _ in 1:n_iter
        redu_time += @elapsed features = reducer.reduct(inp, reducer.parameters)
        flat_time += @elapsed features_flatten = collect(Iterators.flatten(Iterators.flatten(features)))
        cont_time += @elapsed cont_out = CartesianGeneticProgramming.process(cont, features_flatten)
    end
    to_ms = 1000 / n_iter
    redu_time *= to_ms
    flat_time *= to_ms
    cont_time *= to_ms
    redu_time, flat_time, cont_time
end

"""
    function time_dualcgp_ms(
        enco::CGPInd,
        reducer::Reducer,
        cont::CGPInd,
        game_name::String
    )

Time forward pass of complete architecture.
Return time in ms.
"""
function time_dualcgp_ms(
    enco::CGPInd,
    reducer::Reducer,
    cont::CGPInd,
    game_name::String,
    grayscale::Bool,
    downscale::Bool
)
    # Generate input
    g = Game(game_name, 0)
    inp = get_state(g, grayscale, downscale)
    close!(g)
    # Pre-compile
    process(enco, reducer, cont, inp)
    n_iter = 1000
    # Time
    enco_time = 0.0
    redu_time = 0.0
    flat_time = 0.0
    cont_time = 0.0
    for _ in 1:n_iter
        enco_time += @elapsed enco_out = CartesianGeneticProgramming.process(enco, inp)
        redu_time += @elapsed features = reducer.reduct(enco_out, reducer.parameters)
        flat_time += @elapsed features_flatten = collect(Iterators.flatten(Iterators.flatten(features)))
        cont_time += @elapsed cont_out = CartesianGeneticProgramming.process(cont, features_flatten)
    end
    to_ms = 1000 / n_iter
    enco_time *= to_ms
    redu_time *= to_ms
    flat_time *= to_ms
    cont_time *= to_ms
    enco_time, redu_time, flat_time, cont_time
end

function add_baselines(graphs::Vector{Plots.Plot{Plots.GRBackend}}, game::String)
    if haskey(BASELINES, game)
        baselines = BASELINES[game]
        for g in graphs
            for k in keys(baselines)
                if k == "MTCGP"
                    score = baselines[k][1]
                    var = baselines[k][2]
                    hline!(g, [score], ribbon=([var]), color=:gray, label=false)
                else
                    score = baselines[k]
                end
                hline!(g, [score], linestyle=:dash, color=:black, label=false)
                annotate!(0, score, text(k, 7, :bottom, :left), :black)
            end
        end
    end
end

function getlabel(labels::Vector{String}, i::Int64, reducer_type::String)
    if i > length(labels)
        return string(reducer_type)
    else
        return labels[i]
    end
end

function getcolor(colors::Vector{Symbol}, i::Int64, reducer_type::String)
    if i > length(colors)
        if reducer_type == "pooling"
            return :skyblue3
        elseif reducer_type == "centroid"
            return :chocolate1
        else
            return :black
        end
    else
        return colors[i]
    end
end

"""
    plot_cibest(
        exp_dirs::Vector{String},
        games::Vector{String},
        gamename::String,
        labels::Vector{String},
        colors::Vector{Symbol};
        ma::Int64=1
    )

Plot the fitness of the best individual for each generation with
confidence intervals across all experiments using the exact same
configuration dictionary.
"""
function plot_cibest(
    exp_dirs::Vector{String},
    games::Vector{String},
    gamename::String,
    labels::Vector{String},
    colors::Vector{Symbol};
    ma::Int64=1
)
    # 1. Link cfgs and indexes to categories
    n_cat = 0
    cfg2cat = Dict{Dict{Any,Any},Int64}() # Link cfg to category
    ind2cat = Dict{Int64,Int64}() # Link index to category
    for i in eachindex(exp_dirs)
        exp_dir = exp_dirs[i]
        cfg = cfg_from_exp_dir(exp_dir)
        if cfg in keys(cfg2cat) # Link index to existing category
            cat = cfg2cat[cfg]
            ind2cat[i] = cat
        else # Add a new category
            n_cat += 1
            cfg2cat[cfg] = n_cat
            ind2cat[i] = n_cat
        end
    end
    # 2. Fetch logs
    cat2logs = Dict{Int64,Vector{Vector{Float64}}}()
    for i in eachindex(exp_dirs)
        exp_dir = exp_dirs[i]
        log = log_from_exp_dir(exp_dir)
        kernel = OffsetArray(fill(1/(2*ma+1), 2*ma+1), -ma:ma)
        best_i = (ma == 1) ? log.best : imfilter(log.best, kernel)
        cat = ind2cat[i]
        if cat ??? keys(cat2logs)
            push!(cat2logs[cat], best_i)
        else
            cat2logs[cat] = [best_i]
        end
    end
    # 3. Compute mean and confidence intervals
    cat2mean = Dict{Int64,Vector{Float64}}()
    cat2ci = Dict{Int64,Vector{Float64}}()
    for cat in 1:n_cat
        cat2mean[cat] = mean(cat2logs[cat])
        cat2ci[cat] = std(cat2logs[cat])
    end
    # 4. Fetch labels and colors
    @assert length(labels)==n_cat "please provide exactly one label per category"
    @assert length(colors)==n_cat "please provide exactly one color per category"
    cat2lab = Dict{Int64,String}()
    cat2col = Dict{Int64,Symbol}()
    for cat in 1:n_cat
        cat2lab[cat] = labels[cat]
        cat2col[cat] = colors[cat]
        cfg = Dict{Any,Any}()
        for k in keys(cfg2cat)
            if cfg2cat[k] == cat
                cfg = k
            end
        end
        println()
        println("-"^100)
        println("Printing map:")
        println("Number of detected experiments: ", length(cat2logs[cat]))
        println("Label: ", labels[cat])
        println("Color: ", colors[cat])
        println("Configuration: ", cfg)
        println("-"^100)
        println()
    end
    # 5. Plot
    xlabel = "Generation"
    ylabel = string("Best score ", gamename)
    plt = plot(xlabel=xlabel, ylabel=ylabel)
    for cat in 1:n_cat
        y = cat2mean[cat]
        ci = cat2ci[cat]
        lab = cat2lab[cat]
        col = cat2col[cat]
        plot!(plt, y, ribbon=ci, label=lab, color=col)
    end
    #=
    # Re-plot particular experiments
    for i in eachindex(exp_dirs)
        exp_dir = exp_dirs[i]
        cfg = cfg_from_exp_dir(exp_dir)
        log = log_from_exp_dir(exp_dir)
        kernel = OffsetArray(fill(1/(2*ma+1), 2*ma+1), -ma:ma)
        best = (ma == 1) ? log.best : imfilter(log.best, kernel)
        mean = (ma == 1) ? log.mean : imfilter(log.mean, kernel)
        std = (ma == 1) ? log.std : imfilter(log.std, kernel)
        save_gen = cfg["save_gen"]
        x = 1:save_gen:save_gen*length(best)
        plot!(plt, x, best)#, label=label_i, color=color_i)
    end
    =#
    plt
end

function set_graph_dir(
    exp_dirs::Vector{String},
    savedir_index::Int64,
    game::String
)
    exp_dir = exp_dirs[savedir_index]
    set_graph_dir(exp_dir, game)
end

function set_graph_dir(exp_dir::String, game::String)
    exp_name = string(basename(exp_dir)[1:10], "_", game)
    graph_dir = joinpath(dirname(dirname(exp_dir)), "graphs", exp_name)
    mkpath(graph_dir)
    graph_dir
end

function strvec2vec(x::Union{CSV.InlineString,CSV.String31,String})
    x = replace(x, "[" => "")
    x = replace(x, "]" => "")
    [parse(Float64, xi) for xi in split(x, ",")]
end

replace_nan(v::Vector{T}, val::T) where T = map(x -> isnan(x) ? val : x, v)

function retrieve_ucea_statistics(log::CSV.File)
    df = DataFrame(log)
    datadict = Dict()
    datadict["gen"] = Vector{Int64}()
    datadict["best_mean"] = Vector{Float64}()
    datadict["best_means_std"] = Vector{Float64}()
    datadict["best_means_best_score"] = Vector{Float64}()
    datadict["best_means_neval"] = Vector{Int64}()
    datadict["best_score"] = Vector{Float64}()
    datadict["best_scores_neval"] = Vector{Int64}()
    for row in eachrow(df)
        if row.gen_number ??? datadict["gen"]
            push!(datadict["gen"], row.gen_number)
        end
    end
    for gen in datadict["gen"]
        df_gen = filter(row -> row.gen_number == gen, df)
        fitnesses = [strvec2vec(f) for f in df_gen.fitnesses]
        bests = [maximum(f) for f in fitnesses]
        means = [mean(f) for f in fitnesses]
        nevals = [length(f) for f in fitnesses]
        stds = replace_nan([std(f) for f in fitnesses], 0.0)
        best_mean_index = argmax(means)
        best_score_index = argmax(bests)
        push!(datadict["best_mean"], means[best_mean_index])
        push!(datadict["best_means_std"], stds[best_mean_index])
        push!(datadict["best_means_best_score"], bests[best_mean_index])
        push!(datadict["best_means_neval"], nevals[best_mean_index])
        push!(datadict["best_score"], maximum(bests))
        push!(datadict["best_scores_neval"], nevals[best_score_index])
    end
    datadict
end

function process_ucea_results(
    exp_dirs::Vector{String},
    games::Vector{String},
    colors::Vector{Symbol},
    labels::Vector{String};
    do_display::Bool=true,
    do_save::Bool=true,
    savedir_index::Int64=1
)
    @assert all([g == games[1] for g in games])
    game = games[1]
    gamename = gamename_from_romname(game)
    # Create plots
    xl = "Generation"
    yl_fit = string("Score ", gamename)
    yl_neval = string("Number of evaluations ", gamename)
    plt_fit = plot(ylabel=yl_fit, xlabel=xl, legend=:bottomright)
    plt_neval = plot(ylabel=yl_neval, xlabel=xl, legend=:topleft)
    # Fetch logs and plotpareto_gen
    for k in eachindex(exp_dirs)
        exp_dir = exp_dirs[k]
        cfg = cfg_from_exp_dir(exp_dir)
        log = log_from_exp_dir(exp_dir, log_file="logs/logs.csv",
            header=1, sep=";")
        datadict = retrieve_ucea_statistics(log)
        lb_mean = string(labels[k], " best mean")
        lb_best = string(labels[k], " best score of best mean individual")
        lb_best_ever = string(labels[k], " best score across all individuals")
        lb_best_means_neval = string(labels[k], " individual with best mean")
        lb_best_scores_neval = string(labels[k], " individual with best score")
        plot!(plt_fit, datadict["gen"], datadict["best_mean"],
            ribbon=datadict["best_means_std"],
            label=lb_mean, color=colors[k])
        plot!(plt_fit, datadict["gen"], datadict["best_means_best_score"],
            label=lb_best, color=colors[k], linewidth=2)
        plot!(plt_fit, datadict["gen"], datadict["best_score"],
            label=lb_best_ever, color=:red, linewidth=2)
        plot!(plt_neval, datadict["gen"], datadict["best_means_neval"],
            label=lb_best_means_neval, color=colors[k], linewidth=2)
        plot!(plt_neval, datadict["gen"], datadict["best_scores_neval"],
            label=lb_best_scores_neval, color=:red, linewidth=2)
    end
    # Display
    if do_display
        display(plt_fit)
        display(plt_neval)
    end
    # Save
    if do_save
        graph_dir = set_graph_dir(exp_dirs, savedir_index, game)
        savefig(plt_fit, joinpath(graph_dir, "ucea_fitness.png"))
        savefig(plt_neval, joinpath(graph_dir, "ucea_neval.png"))
    end
end

tofilename(s::String) = replace(lowercase(s), " " => "_")
pareto_key(i::Int64) = string("pareto_", i)
rawfit_max_key(i::Int64) = string("obj_", i, "_best_rawfit")
rawfit_mea_key(i::Int64) = string("obj_", i, "_mean_rawfit")
rawfit_std_key(i::Int64) = string("obj_", i, "_std_rawfit")
norfit_max_key(i::Int64) = string("obj_", i, "_best_norfit")
norfit_mea_key(i::Int64) = string("obj_", i, "_mean_norfit")
norfit_std_key(i::Int64) = string("obj_", i, "_std_norfit")

function retrieve_nsga2_statistics(
    log::CSV.File;
    pareto_gen::Vector{Int64}=Vector{Int64}()
)
    n_obj = length(strvec2vec(log[1].fitness))
    datadict = Dict()
    datadict["gen"] = Vector{Int64}()
    for i in 1:n_obj
        datadict[rawfit_max_key(i)] = Vector{Float64}()
        datadict[rawfit_mea_key(i)] = Vector{Float64}()
        datadict[rawfit_std_key(i)] = Vector{Float64}()
        datadict[norfit_max_key(i)] = Vector{Float64}()
        datadict[norfit_mea_key(i)] = Vector{Float64}()
        datadict[norfit_std_key(i)] = Vector{Float64}()
    end
    for row in log
        if row.gen_number ??? datadict["gen"]
            push!(datadict["gen"], row.gen_number)
        end
    end
    for gen in datadict["gen"]
        rawfit = [strvec2vec(r.fitness) for r in log[log.gen_number .== gen]]
        norfit = [strvec2vec(r.normalized_fitness) for r in log[log.gen_number .== gen]]
        for i in 1:n_obj
            push!(datadict[rawfit_max_key(i)], maximum([f[i] for f in rawfit]))
            push!(datadict[rawfit_mea_key(i)], mean([f[i] for f in rawfit]))
            push!(datadict[rawfit_std_key(i)], std([f[i] for f in rawfit]))
            push!(datadict[norfit_max_key(i)], maximum([f[i] for f in norfit]))
            push!(datadict[norfit_mea_key(i)], mean([f[i] for f in norfit]))
            push!(datadict[norfit_std_key(i)], std([f[i] for f in norfit]))
        end
    end
    for gen in pareto_gen
        datadict[pareto_key(gen)] = [strvec2vec(r.normalized_fitness) for r in log[log.gen_number .== gen]]
    end
    datadict
end

function process_nsga2_results(
    exp_dirs::Vector{String},
    games::Vector{String},
    objectives_names::Vector{String},
    colors::Vector{Symbol},
    labels::Vector{String};
    pareto_gen::Vector{Int64}=Vector{Int64}(),
    pareto_xlim::Tuple=(0, 1),
    pareto_ylim::Tuple=(0, 1),
    do_display::Bool=true,
    do_save::Bool=true,
    savedir_index::Int64=1
)
    @assert all([g == games[1] for g in games])
    game = games[1]
    gamename = gamename_from_romname(game)
    # Create plots
    xl = "Generation"
    plt_rawfit = Vector{Plots.Plot}()
    plt_norfit = Vector{Plots.Plot}()
    plt_pareto = Vector{Plots.Plot}()
    for i in eachindex(objectives_names)
        yl_raw = string(objectives_names[i], " (", gamename, ")")
        yl_nor = string("Normalized ", objectives_names[i], " (", gamename, ")")
        push!(plt_rawfit, plot(ylabel=yl_raw, xlabel=xl))
        push!(plt_norfit, plot(ylabel=yl_nor, xlabel=xl))
    end
    for gen in pareto_gen
        title = string("Pareto front ", gamename, " (generation: ", gen, ")")
        xl_par = objectives_names[1]
        yl_par = objectives_names[2]
        push!(plt_pareto, plot(ylabel=yl_par, xlabel=xl_par, title=title))
    end
    # Fetch logs and plotpareto_gen
    for k in eachindex(exp_dirs)
        exp_dir = exp_dirs[k]
        cfg = cfg_from_exp_dir(exp_dir)
        log = log_from_exp_dir(exp_dir, log_file="logs/logs.csv",
            header=1, sep=";")
        datadict = retrieve_nsga2_statistics(log, pareto_gen=pareto_gen)
        for i in eachindex(objectives_names)
            best_lb = string(labels[k], " best")
            mean_lb = string(labels[k], " mean")
            plot!(plt_rawfit[i], datadict["gen"], datadict[rawfit_max_key(i)],
                label=best_lb, color=colors[k], linewidth=2)
            plot!(plt_rawfit[i], datadict["gen"], datadict[rawfit_mea_key(i)],
                ribbon=datadict[rawfit_std_key(i)], label=mean_lb,
                color=colors[k])
            plot!(plt_norfit[i], datadict["gen"], datadict[norfit_max_key(i)],
                label=best_lb, color=colors[k], linewidth=2)
            plot!(plt_norfit[i], datadict["gen"], datadict[norfit_mea_key(i)],
                ribbon=datadict[norfit_std_key(i)], label=mean_lb,
                color=colors[k])
        end
        for i in eachindex(pareto_gen)
            x = [nf[1] for nf in datadict[pareto_key(pareto_gen[i])]]
            y = [nf[2] for nf in datadict[pareto_key(pareto_gen[i])]]
            plot!(plt_pareto[i], x, y, seriestype = :scatter, xlims=pareto_xlim,
                ylims=pareto_ylim, label=labels[k], markercolor=colors[k])
        end
    end
    # Display
    if do_display
        for i in eachindex(plt_rawfit)
            display(plt_rawfit[i])
            #display(plt_norfit[i])
        end
        for i in eachindex(pareto_gen)
            display(plt_pareto[i])
        end
    end
    # Save
    if do_save
        graph_dir = set_graph_dir(exp_dirs, savedir_index, game)
        for i in eachindex(objectives_names)
            raw_name = tofilename(string(objectives_names[i], "_best.png"))
            nor_name = tofilename(string(objectives_names[i], "_normalized_best.png"))
            savefig(plt_rawfit[i], joinpath(graph_dir, raw_name))
            savefig(plt_norfit[i], joinpath(graph_dir, nor_name))
        end
        for i in eachindex(pareto_gen)
            par_name = tofilename(string("pareto_gen_", pareto_gen[i], ".png"))
            savefig(plt_pareto[i], joinpath(graph_dir, par_name))
        end
    end
end

"""
    function process_results(
        exp_dirs::Vector{String},
        games::Vector{String},
        dotime::Bool,
        dosave::Bool;
        savedir_index::Int64=1,
        ma::Int64=1,
        baselines::Bool=false,
        labels::Vector{String}=Vector{String}(),
        colors::Vector{Symbol}=Vector{Symbol}(),
        plotci::Bool=false,
        cilabels::Vector{String}=Vector{String}(),
        cicolors::Vector{Symbol}=Vector{Symbol}()
    )

Main results plot/print method.
"""
function process_results(
    exp_dirs::Vector{String},
    games::Vector{String},
    dotime::Bool,
    dosave::Bool;
    savedir_index::Int64=1,
    ma::Int64=1,
    baselines::Bool=false,
    labels::Vector{String}=Vector{String}(),
    colors::Vector{Symbol}=Vector{Symbol}(),
    plotci::Bool=false,
    cilabels::Vector{String}=Vector{String}(),
    cicolors::Vector{Symbol}=Vector{Symbol}()
)
    # Init graphs
    game = games[1]
    gamename = gamename_from_romname(game)
    xl = "Generation"
    yl_best = string("Best score ", gamename)
    yl_mean = string("Mean score ", gamename)
    plt_best = plot(ylabel=yl_best, xlabel=xl)
    plt_mean = plot(ylabel=yl_mean, xlabel=xl)
    if plotci
        plt_mbst = plot_cibest(exp_dirs, games, gamename, cilabels, cicolors, ma=ma)
    end

    for i in eachindex(exp_dirs)
        exp_dir = exp_dirs[i]
        cfg = cfg_from_exp_dir(exp_dir)
        log = log_from_exp_dir(exp_dir)

        # Plots
        reducer_type = cfg["reducer"]["type"]
        label_i = getlabel(labels, i, reducer_type)
        color_i = getcolor(colors, i, reducer_type)
        kernel = OffsetArray(fill(1/(2*ma+1), 2*ma+1), -ma:ma)
        best = (ma == 1) ? log.best : imfilter(log.best, kernel)
        mean = (ma == 1) ? log.mean : imfilter(log.mean, kernel)
        std = (ma == 1) ? log.std : imfilter(log.std, kernel)
        save_gen = cfg["save_gen"]
        x = 1:save_gen:save_gen*length(best)
        plot!(plt_best, x, best, label=label_i, color=color_i)
        plot!(plt_mean, x, mean, ribbon=std, label=label_i, color=color_i)

        # Append info to print
        p = []
        push!(p, ["Game", games[i]])
        push!(p, ["Number gen", length(log) * cfg["save_gen"]])
        push!(p, ["1st gen", ""])
        push!(p, ["  - best", log[1].best])
        push!(p, ["  - mean", log[1].mean])
        push!(p, ["  - std", log[1].std])
        push!(p, ["end gen", ""])
        push!(p, ["  - best", log[end].best])
        push!(p, ["  - mean", log[end].mean])
        push!(p, ["  - std", log[end].std])
        push!(p, ["Reducer", reducer_type])
        if cfg["reducer"]["type"] == "centroid"
            push!(p, ["  - n_centroids", cfg["reducer"]["n_centroids"]])
        else
            push!(p, ["  - features_size", cfg["reducer"]["features_size"]])
            push!(p, ["  - pooling_function", cfg["reducer"]["pooling_function"]])
        end

        # Timer
        if dotime
            push!(p, ["Forward pass timing (ms)", ""])
            is_dual = isfile(joinpath(exp_dirs[i], "logs/encoder.csv"))
            total_time = 0.0
            grayscale = cfg["grayscale"]
            downscale = cfg["downscale"]
            if is_dual
                enco, reducer, cont = get_last_dualcgp(exp_dirs[i], games[i], cfg)
                enco_time, redu_time, flat_time, cont_time = time_dualcgp_ms(
                    enco, reducer, cont, games[i], grayscale, downscale
                )
                push!(p, ["  - Encoder", enco_time])
                total_time += enco_time
            else
                reducer, cont = get_last_monocgp(exp_dirs[i], games[i], cfg)
                redu_time, flat_time, cont_time = time_monocgp_ms(
                    reducer, cont, games[i], grayscale, downscale
                )
            end
            total_time += redu_time
            total_time += flat_time
            total_time += cont_time
            push!(p, ["  - Reducer", redu_time])
            push!(p, ["  - Flattening", flat_time])
            push!(p, ["  - Controller", cont_time])
            push!(p, ["  - Total", total_time])
        end

        # Finish push and print
        l = maximum([length(k) for k in [pr[1] for pr in p]])
        println()
        for k in p
            println(string(k[1], " "^(l-length(k[1])), " : ", k[2]))
        end
    end
    if baselines
        add_baselines([plt_best, plt_mean], game)
    end
    display(plt_best)
    display(plt_mean)
    if plotci
        if baselines
            add_baselines([plt_mbst], game)
        end
        display(plt_mbst)
    end

    if dosave
        graph_dir = set_graph_dir(exp_dirs, savedir_index, game)
        savefig(plt_best, joinpath(graph_dir, "best.png"))
        savefig(plt_mean, joinpath(graph_dir, "mean.png"))
        if plotci
            savefig(plt_mbst, joinpath(graph_dir, "bestci.png"))
        end
    end
end
