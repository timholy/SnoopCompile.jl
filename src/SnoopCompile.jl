module SnoopCompile

export
    snoop_on,
    snoop_off,
    @snoop

function snoop_path()
    snoopdir = Base.find_in_path("SnoopCompile.jl")
    isempty(snoopdir) && error("SnoopCompile is not your path, please fix (e.g., push!(LOAD_PATH, \"/path/to/SnoopCompile\"))")
    splitdir(snoopdir)[1]
end

function snoop_on()
    cd(snoop_path()) do
        run(`sh snoop.sh ""`)
    end
end

function snoop_off()
    cd(snoop_path()) do
        run(`sh snoop.sh "--reverse"`)
    end
end

macro snoop(filename, commands)
    quote
        io = open($filename, "w")
        ccall(:jl_dump_compiles, Void, (Ptr{Void},), io.handle)
        try
            $(esc(commands))
        finally
            ccall(:jl_dump_compiles, Void, (Ptr{Void},), C_NULL)
            close(io)
        end
    end
end

function read(filename)
    data = readdlm(filename, '\t')
    # Save the most costly for last
    p = sortperm(data[:,1])
    data[p,:]
end

# calls is the second column of the output of read_snoop,
# after selecting which ones you want to keep.
function parcel(calls; blacklist=UTF8String[])
    pc = Dict{UTF8String,Vector{UTF8String}}()
    discards = UTF8String[]
    for c in calls
        contains(c, "#") && continue
        contains(c, "<:") && continue
        if any(b->contains(c, b), blacklist)
            continue
        end
        fargs = split(c, '(')
        if length(fargs) != 2
            error("c is ", c, ", fargs is ", fargs)
        end
        # Make sure this is a generic function
        fpath = filter(x->!isempty(x), split(fargs[1], "."))
        local mod
        try
            mod = eval(Main, parse(join(fpath[1:end-1], ".")))
        catch
            continue
        end
        if !isdefined(mod, symbol(fpath[end]))
            println("skipping ", fargs[1])
            continue
        end
        fname = convert(UTF8String, fpath[end])
        chr = first(fname)
        if !isalnum(chr) && chr!='_'
            continue   # operators just cause too much trouble...
            #                fname = string('(', fname, ')')  # + -> (+)
        end
        fname = string(mod, ".", fname)
        args = fargs[2]
        if length(args) > 1
            # we insert a comma to ensure tuples for single-argument functions
            args = string("(", args[1:end-1], ",)")
        else
            args = "()"
        end
        pcstring = string("    precompile(", fname, ", ", args, ")")
        # Add to the appropriate dictionary
        modname = fpath[1]
        try
            eval(Main.eval(symbol(modname)), parse(args))
        catch
            push!(discards, pcstring)
            continue
        end
        if !haskey(pc, modname)
            pc[modname] = UTF8String[]
        end
        push!(pc[modname], pcstring)
    end
    pc, discards
end

# Write each modules' precompiles to a separate file
function write(pc, prefix=pwd())
    if !isdir(prefix)
        mkpath(prefix)
    end
    for (k,v) in pc
        open(joinpath(prefix, "precompile_$k.jl"), "w") do io
            println(io, "function _precompile_()")
            println(io, "    ccall(:jl_generating_output, Cint, ()) == 1 || return nothing")
            for ln in v
                println(io, ln)
            end
            println(io, "end")
        end
    end
end

end # module
