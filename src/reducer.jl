export Reducer, PoolingReducer, CentroidReducer, AbstractReducer

# using OpenCV
using Statistics
using TiledIteration
using Hungarian
using Images
using ImageMorphology
using LinearAlgebra

abstract type AbstractReducer end

struct Reducer <: AbstractReducer
    reduct::Function
    parameters::Dict
end

"""
    PoolingReducer(f::Function, size::Int64)

Pooling reducer constructor.
"""
function PoolingReducer(f::Function, size::Int64)
    p = Dict("pooling_function"=>f, "size"=>size)
    Reducer(pooling_reduction, p)
end

"""
    CentroidReducer(
        n_centroids::Int64,
        n_in::Int64,
        img_size::Tuple{Int64,Int64}
    )

Centroid reducer constructor.
"""
function CentroidReducer(n_centroids::Int64, n_in::Int64,
                         img_size::Tuple{Int64,Int64})
    p = Dict(
        "n"=>n_centroids,
        "c_prev"=>Array{Array{Tuple{Float64,Float64},1},1}(undef, n_in),
        "a_prev"=>Array{Array{Int64,1},1}(undef, n_in),
        "img_size"=>img_size
    )
    Reducer(centroid_reduction, p)
end

"""
    reorder_features(
        c1::Array{Tuple{Float64,Float64},1},
        a1::Array{Int64,1},
        c2::Array{Tuple{Float64,Float64},1},
        a2::Array{Int64,1}
    )

Reorder the features contained in c2, a2 by making a best match with c1, a1.
"""
function reorder_features(
    c1::Array{Tuple{Float64,Float64},1},
    a1::Array{Int64,1},
    c2::Array{Tuple{Float64,Float64},1},
    a2::Array{Int64,1}
)
    weights = zeros(length(c1), length(c1))
    for i in eachindex(c1)
        for j in eachindex(c2)
            weights[i, j] = norm(c1[i] .- c2[j]) + abs(a1[i] - a2[j])
        end
    end
    assignment, cost = hungarian(weights)  # 5.680 μs (40 allocations: 5.44 KiB)
    a2[assignment], c2[assignment]
end

"""
    normalized_centroids(
        c::Array{Tuple{Float64,Float64},1},
        img_size::Tuple{Int64,Int64}
    )

Normalize the input centroid vector to [0.0, 1.0].
Requires the image size as a 2D tuple.
"""
function normalized_centroids(c::Array{Tuple{Float64,Float64},1},
                              img_size::Tuple{Int64,Int64})
    c_norm = Array{Tuple{Float64,Float64},1}(undef, length(c))
    for i in eachindex(c)
        c_norm[i] = c[i] ./ img_size
    end
    c_norm
end

"""
    centroid_reduction(xs::Array{Array{UInt8,2},1}, parameters::Dict)

Generic centroid reduction function for several images (sequential application).
"""
function centroid_reduction(xs::Array{Array{UInt8,2},1}, parameters::Dict)
    fs = Array{Array{Tuple{Float64,Float64},1},1}(undef, length(xs))
    for i in eachindex(xs)
        if isdefined(parameters["c_prev"], i)
            c_prev = parameters["c_prev"][i]
            a_prev = parameters["a_prev"][i]
        else
            c_prev = nothing
            a_prev = nothing
        end
        c, a = centroid_reduction(xs[i], parameters["n"], c_prev, a_prev)
        fs[i] = normalized_centroids(c, parameters["img_size"])
        parameters["c_prev"][i] = c
        parameters["a_prev"][i] = a
    end
    return fs
end

"""
    centroid_reduction(
        x::Array{UInt8, 2},
        c_prev::Array{Tuple{Float64,Float64},1},
        a_prev::Array{Int64,1}
    )

Given an image, return the centroids and the boxes areas of the `n` largest
connected components, `n` being defined in the parameters dictionary.
Fill with zeros if there are less than `n` components.
"""
function centroid_reduction(
        x::Array{UInt8, 2},
        n::Int64,
        c_prev::Union{Array{Tuple{Float64,Float64},1}, Nothing},
        a_prev::Union{Array{Int64,1}, Nothing}
    )
    labels = label_components(x)
    boxes = component_boxes(labels)
    centroids = component_centroids(labels)
    # popfirst!(centroids)  # remove largest
    areas = [abs(b[1][1]-b[2][1]-1) * abs(b[1][2]-b[2][2]-1) for b in boxes]
    p = sortperm(areas, rev=true)
    centroids = centroids[p]
    areas = areas[p]
    c = fill((0.0, 0.0), n)
    a = fill(0, n)
    for i in eachindex(centroids)
        c[i] = centroids[i]
        a[i] = areas[i]
        if i == n
            break
        end
    end
    if c_prev != nothing && a_prev != nothing
        a, c = reorder_features(parameters["c_prev"], parameters["a_prev"], c, a)
    end
    c_flat = collect(Iterators.flatten(c))
    c, a
end

"""
    pooling_reduction(xs::Array{Array{UInt8,2},1}, parameters::Dict)

Generic pooling function for several images (sequential application).
"""
function pooling_reduction(xs::Array{Array{UInt8,2},1}, parameters::Dict)
    fs = Array{Array{Float64,2},1}(undef, length(xs))
    for i in eachindex(xs)
        fs[i] = pooling_reduction(xs[i], parameters)
    end
    return fs
end

"""
    pooling_reduction(x::Array{UInt8,2}, parameters::Dict)

Generic pooling function for a single image.
"""
function pooling_reduction(x::Array{UInt8,2}, parameters::Dict)
    outsz = (parameters["size"], parameters["size"])
    # out = Array{eltype(x), ndims(x)}(undef, outsz)
    out = Array{Float64, ndims(x)}(undef, outsz)
    tilesz = ceil.(Int, size(x)./outsz)
    R = TileIterator(axes(x), tilesz)
    i = 1
    for tileaxs in R
       out[i] = parameters["pooling_function"](view(x, tileaxs...))
       i += 1
    end
    return out ./ 255.0
end
