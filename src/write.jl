# Write precompiles for userimg.jl
function write(io::IO, pc::Vector{<:AbstractString})
    for ln in pc
        println(io, ln)
    end
end

function write(filename::AbstractString, pc::Vector)
    path, fn = splitdir(filename)
    if !isdir(path)
        mkpath(path)
    end
    ret = nothing
    open(filename, "w") do io
        ret = write(io, pc)
    end
    return ret
end

"""
    write(prefix::AbstractString, pc::Dict; always::Bool = false)

Write each modules' precompiles to a separate file.  If `always` is
true, the generated function will always run the precompile statements
when called, otherwise the statements will only be called during
package precompilation.
"""
function write(prefix::AbstractString, pc::Dict; always::Bool = false)
    if !isdir(prefix)
        mkpath(prefix)
    end
    for (k, v) in pc
        open(joinpath(prefix, "precompile_$k.jl"), "w") do io
            if any(str->occursin("__lookup", str), v)
                println(io, lookup_kwbody_str)
            end
            println(io, "function _precompile_()")
            !always && println(io, "    ccall(:jl_generating_output, Cint, ()) == 1 || return nothing")
            for ln in sort(v)
                println(io, "    ", ln)
            end
            println(io, "end")
        end
    end
end
