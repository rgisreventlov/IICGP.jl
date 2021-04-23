export ReducingFunctions

module ReducingFunctions

using OpenCV

function nearest_reduction(m::T; s::Int64=5) where {T <: OpenCV.InputArray}
    # dsize = OpenCV.Size(convert(Int32, s), convert(Int32, s))
    return OpenCV.resize(m, OpenCV.Size(convert(Int32, s), convert(Int32, s)),
                         m, 1.0, 1.0, OpenCV.INTER_NEAREST)
end

function linear_reduction(m::T; s::Int64=5) where {T <: OpenCV.InputArray}
    # dsize = OpenCV.Size(convert(Int32, s), convert(Int32, s))
    return OpenCV.resize(m, OpenCV.Size(convert(Int32, s), convert(Int32, s)),
                         m, 1.0, 1.0, OpenCV.INTER_LINEAR)
end

function area_reduction(m::T; s::Int64=5) where {T <: OpenCV.InputArray}
    # dsize = OpenCV.Size(convert(Int32, s), convert(Int32, s))
    return OpenCV.resize(m, OpenCV.Size(convert(Int32, s), convert(Int32, s)),
                         m, 1.0, 1.0, OpenCV.INTER_AREA)
end

function cubic_reduction(m::T; s::Int64=5) where {T <: OpenCV.InputArray}
    # dsize = OpenCV.Size(convert(Int32, s), convert(Int32, s))
    return OpenCV.resize(m, OpenCV.Size(convert(Int32, s), convert(Int32, s)),
                         m, 1.0, 1.0, OpenCV.INTER_CUBIC)
end

function lanczos_reduction(m::T; s::Int64=5) where {T <: OpenCV.InputArray}
    # dsize = OpenCV.Size(convert(Int32, s), convert(Int32, s))
    return OpenCV.resize(m, OpenCV.Size(convert(Int32, s), convert(Int32, s)),
                         m, 1.0, 1.0, OpenCV.INTER_LANCZOS4)
end

end
