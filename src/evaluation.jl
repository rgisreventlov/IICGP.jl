export fitness_evaluate

"""
    function null_evaluate(i::CGPInd, j::CGPInd)

Default evaluation function for two CGP individuals.
"""
function null_evaluate(i::CGPInd, j::CGPInd)
    return -Inf
end

"""
    function fitness_evaluate(e::CGPEvolution; fitness::Function=null_evaluate)

Sets the fitness of each individual to the Array of values returned by fitness.
Multithreaded option enabled in this version.
"""
function fitness_evaluate(e::CGPEvolution, fitness::Function=null_evaluate)
    @sync for i in eachindex(e.population)
        Threads.@spawn begin
            e.population[i].fitness[:] = fitness(e.population[i])[:]
        end
    end
end

"""
    function fitness_evaluate(e::DualCGPEvolution, fitness::Function=null_evaluate)

Sets the fitness of each individual to the maximum value of the fitness matrix
in the dual CGP evolution framework.

TODOs:
- handle multi dimensional fitness in coevolution
"""
function fitness_evaluate(e::DualCGPEvolution, fitness::Function=null_evaluate)
    n_enco = e.encoder_config.n_population
    n_cont = e.controller_config.n_population
    fitness_matrix = Array{Float64}(undef, n_enco, n_cont)

    println("###### Enter fitness evaluate") # TODO remove
    flush(stdout) # TODO remove

	# FORMER method with @sync
    #=
	@sync for i in 1:n_enco
        for j in 1:n_cont
		    println("###### About to do evaluation $i $j") # TODO remove
		    flush(stdout) # TODO remove
            encoder_i = IPCGPInd(e.encoder_config, e.encoder_population[i].chromosome)
            controller_j = CGPInd(e.controller_config, e.controller_population[j].chromosome)
            Threads.@spawn begin
                fitness_matrix[i, j] = fitness(encoder_i, controller_j)[1] # Currently, only pick 1st fitness dimension
            end
        end
    end
	=#

	# NEW method with Threads.@threads
	indexes = [(i, j) for i in 1:n_enco for j in 1:n_cont]
    Threads.@threads for l in 1:(n_enco+n_cont)
        i, j = indexes[l]
		println("###### About to do evaluation $i $j") # TODO remove
		flush(stdout) # TODO remove
		enco_i = IPCGPInd(e.encoder_config, e.encoder_population[i].chromosome)
		cont_j = CGPInd(e.controller_config, e.controller_population[j].chromosome)
		fitness_matrix[i,j] = fitness(enco_i, cont_j)[1] # Currently, only pick 1st fitness dimension
    end

    println("###### Completed evaluation") # TODO remove
    flush(stdout) # TODO remove

    for i in eachindex(e.encoder_population)
        e.encoder_population[i].fitness[1] = maximum(fitness_matrix[i,:])
    end
    for j in eachindex(e.controller_population)
        e.controller_population[j].fitness[1] = maximum(fitness_matrix[:,j])
    end
    println("###### Exit fitness evaluate") # TODO remove
    flush(stdout) # TODO remove
end
