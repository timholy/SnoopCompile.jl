"""
    times, info = SnoopCompile.read_snoop_llvm("func_names.csv", "llvm_timings.yaml"; tmin_secs=0.0)

Reads the log file produced by the compiler and returns the structured representations.

The results will only contain modules that took longer than `tmin_secs` to optimize.

## Return value
- `times` contains the time spent optimizing each module, as a Pair from the time to an
array of Strings, one for every MethodInstance in that llvm module.
- `info` is a Dict containing statistics for each MethodInstance encountered, from before
and after optimization, including number of instructions and number of basicblocks.

## Example
```julia
julia> @snoop_llvm "func_names.csv" "llvm_timings.yaml" begin
           using InteractiveUtils
           @eval InteractiveUtils.peakflops()
       end
Launching new julia process to run commands...
done.

julia> times, info = SnoopCompile.read_snoop_llvm("func_names.csv", "llvm_timings.yaml", tmin_secs = 0.025);

julia> times
3-element Vector{Pair{Float64, Vector{String}}}:
 0.028170923 => ["Tuple{typeof(LinearAlgebra.copy_transpose!), Array{Float64, 2}, Base.UnitRange{Int64}, Base.UnitRange{Int64}, Array{Float64, 2}, Base.UnitRange{Int64}, Base.UnitRange{Int64}}"]
 0.031356962 => ["Tuple{typeof(Base.copyto!), Array{Float64, 2}, Base.UnitRange{Int64}, Base.UnitRange{Int64}, Array{Float64, 2}, Base.UnitRange{Int64}, Base.UnitRange{Int64}}"]
 0.149138788 => ["Tuple{typeof(LinearAlgebra._generic_matmatmul!), Array{Float64, 2}, Char, Char, Array{Float64, 2}, Array{Float64, 2}, LinearAlgebra.MulAddMul{true, true, Bool, Bool}}"]

julia> info
Dict{String, NamedTuple{(:before, :after), Tuple{NamedTuple{(:instructions, :basicblocks), Tuple{Int64, Int64}}, NamedTuple{(:instructions, :basicblocks), Tuple{Int64, Int64}}}}} with 3 entries:
  "Tuple{typeof(LinearAlgebra.copy_transpose!), Ar… => (before = (instructions = 651, basicblocks = 83), after = (instructions = 348, basicblocks = 40…
  "Tuple{typeof(Base.copyto!), Array{Float64, 2}, … => (before = (instructions = 617, basicblocks = 77), after = (instructions = 397, basicblocks = 37…
  "Tuple{typeof(LinearAlgebra._generic_matmatmul!)… => (before = (instructions = 4796, basicblocks = 824), after = (instructions = 1421, basicblocks =…
```
"""
function read_snoop_llvm(func_csv_file, llvm_yaml_file; tmin_secs=0.0)
    func_csv = _read_snoop_llvm_csv(func_csv_file)
    llvm_yaml = YAML.load_file(llvm_yaml_file)
    filter!(llvm_yaml) do llvm_module
        llvm_module["before"] !== nothing
    end

    jl_names = Dict(r[1]::String => r[2]::String for r in func_csv)

    # `get`, but with a warning
    try_get_jl_name(name) = if name in keys(jl_names)
            jl_names[name]
        else
            @warn "Couldn't find $name"
            name
        end

    time_secs(llvm_module) = llvm_module["time_ns"] / 1e9

    times = [
        time_secs(llvm_module) => [
            try_get_jl_name(name)
            for (name,_) in llvm_module["before"]
        ] for llvm_module in llvm_yaml
        if time_secs(llvm_module) > tmin_secs
    ]

    info = Dict(
        try_get_jl_name(name) => (;
            before = (;
                instructions = before_stats["instructions"],
                basicblocks = before_stats["basicblocks"],
            ),
            after = (;
                instructions = after_stats["instructions"],
                basicblocks = after_stats["basicblocks"],
            ),
        )
        for llvm_module in llvm_yaml
        for (name, before_stats) in llvm_module["before"]
        for (name, after_stats)  in llvm_module["after"]
        if time_secs(llvm_module) > tmin_secs
    )


    # sort times so that the most costly items are displayed last
    return (sort(times), info)
end


"""
`SnoopCompile._read_snoop_llvm_csv("compiledata.csv")` reads the log file produced by the
compiler and returns the function names as an array of pairs.
"""
function _read_snoop_llvm_csv(filename)
    data = Vector{Pair{String,String}}()
    # Format is [^\t]+\t[^\t]+. That is, tab-separated entries. No quotations or other
    # whitespace are considered.
    for line in eachline(filename)
        c_name, jl_type = split2(line, '\t')
        (length(c_name) < 2 || length(jl_type) < 2) && continue
        push!(data, c_name => jl_type)
    end
    return data
end