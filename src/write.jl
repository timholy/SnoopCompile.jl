# Write precompiles for userimg.jl
const warnpcfail_str = """
# Use
#    @warnpcfail precompile(args...)
# if you want to be warned when a precompile directive fails
macro warnpcfail(ex::Expr)
    modl = __module__
    file = __source__.file === nothing ? "?" : String(__source__.file)
    line = __source__.line
    quote
        \$(esc(ex)) || @warn \"\"\"precompile directive
     \$(\$(Expr(:quote, ex)))
 failed. Please report an issue in \$(\$modl) (after checking for duplicates) or remove this directive.\"\"\" _file=\$file _line=\$line
    end
end
"""

function write(io::IO, pc::Vector{<:AbstractString}; writewarnpcfail::Bool=true)
    writewarnpcfail && println(io, warnpcfail_str, '\n')
    for ln in pc
        println(io, ln)
    end
end

function write(filename::AbstractString, pc::Vector; kwargs...)
    path, fn = splitdir(filename)
    if !isdir(path)
        mkpath(path)
    end
    return open(filename, "w") do io
        write(io, pc)
    end
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
            println(io, warnpcfail_str, '\n')
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
