export imshow, display_buffer

# using CartesianGeneticProgramming
using Plots

#=
# DEPRECATED
"""
    imshow(m::T) where {T <: OpenCV.InputArray}

Show input image using functions `imshow` and `waitKey` from OpenCV Julia
binding.
"""
function imshow(m::T) where {T <: OpenCV.InputArray}
    OpenCV.imshow("Image", m)
    OpenCV.waitKey(Int32(0))
end

"""
    imshow(m::T; enlargement::Int64) where {T <: OpenCV.InputArray}

Show enlarged input image using functions `imshow` and `waitKey` from OpenCV
Julia binding.
The enlargement factor is given by the `enlargement` input parameter.

Examples:

    IICGP.imshow(m)
    IICGP.imshow(m, 2)
    IICGP.imshow(m, 0.5)
"""
function imshow(m::T, enlargement::E) where {T <: OpenCV.InputArray, E <: Union{Int64, Float64}}
    n_cols = convert(Int32, size(m)[2] * enlargement)
    n_rows = convert(Int32, size(m)[3] * enlargement)
    new_size = OpenCV.Size(n_cols, n_rows)
    enlarged = OpenCV.resize(m, new_size, m, 1.0, 1.0, OpenCV.INTER_NEAREST)
    imshow(enlarged)
end
=#


"""
    function implot(img::AbstractArray; kwargs...)

Plot input image using heatmap.
Magnitude parameter may be precised using the `clim` keyword. The default value
is set to `clim=(0,255)`. Using `clim="auto"` amounts to take the maximum of
the input image as maximum magnitude.

Examples:

    implot(m)
    implot(m, clim="auto")
    implot(m, clim=(1, 10))
"""
function implot(img::AbstractArray; kwargs...)
    kwargs_dict = Dict(kwargs)
    if haskey(kwargs_dict, :clim)
        if kwargs_dict[:clim] == "auto"
            clim = (0, maximum(img))
        else
            clim = kwargs_dict[:clim]
        end
    else
        clim = (0, 255)
    end
    if ndims(img) == 3
        img = img[1,:,:]
    end
    heatmap(img, yflip=true, color=:grays, clim=clim)
end

"""
    function display_buffer(ind::CGPInd, enlargement::E=1, indexes::Array{Int64}) where {E <: Union{Int64, Float64}}

Display the images contained in each node in the input IPCGP individual.

Examples:

    IICGP.display_buffer(ind)
    IICGP.display_buffer(ind, 2)
    IICGP.display_buffer(ind, indexes=1:3)
    IICGP.display_buffer(ind, 2, indexes=1:3)
"""
function display_buffer(ind::CGPInd, enlargement::E=1; indexes=eachindex(ind.buffer)) where {E <: Union{Int64, Float64}}
    for i in indexes
        imshow(ind.buffer[i], enlargement)
    end
end


"""
    plot_encoding(n_in::Int64, buffer::Array{Array{UInt8, 2}, 1}, features::AbstractArray)

Plot the complete encoding pipeline from input to projection on feature space.
"""
function plot_encoding(n_in::Int64, buffer::Array{Array{UInt8, 2}, 1},
                       features::AbstractArray)
    n_cols = max(n_in, length(features), length(buffer)-n_in)
    p = plot(layout=grid(3, n_cols), leg=false, framestyle=:none) #axis=nothing)
    for i in 1:n_in
        plot!(p[i], buffer[i], seriestype=:heatmap, ratio=:equal, color=:grays)
    end
    for i in n_in+1:length(buffer)
        plot!(p[2,i-n_in], buffer[i], seriestype=:heatmap, ratio=:equal, color=:grays, flip=true)
    end
    for i in eachindex(features)
        plot!(p[3,i], features[i], seriestype=:heatmap, ratio=:equal, color=:grays, flip=true)
    end
    p
end
