export @snoop_llvm

using Serialization

"""
```
@snoop_llvm "func_names.csv" "llvm_timings.yaml" begin
    # Commands to execute, in a new process
end
```
causes the julia compiler to log timing information for LLVM optimization during the
provided commands to the files "func_names.csv" and "llvm_timings.yaml". These files can
be used for the input to `SnoopCompile.read_snoop_llvm("func_names.csv", "llvm_timings.yaml")`.

The logs contain the amount of time spent optimizing each "llvm module", and information
about each module, where a module is a collection of functions being optimized together.
"""
macro snoop_llvm(flags, func_file, llvm_file, commands)
    return :(snoop_llvm($(esc(flags)), $(esc(func_file)), $(esc(llvm_file)), $(QuoteNode(commands))))
end
macro snoop_llvm(func_file, llvm_file, commands)
    return :(snoop_llvm(String[], $(esc(func_file)), $(esc(llvm_file)), $(QuoteNode(commands))))
end

function snoop_llvm(flags, func_file, llvm_file, commands)
    println("Launching new julia process to run commands...")
    # addprocs will run the unmodified version of julia, so we
    # launch it as a command.
    code_object = """
            using Serialization
            while !eof(stdin)
                Core.eval(Main, deserialize(stdin))
            end
            """
    process = open(`$(Base.julia_cmd()) $flags --eval $code_object --project=$(Base.active_project())`, stdout, write=true)
    serialize(process, quote
        let func_io = open($func_file, "w"), llvm_io = open($llvm_file, "w")
            ccall(:jl_dump_emitted_mi_name, Nothing, (Ptr{Nothing},), func_io.handle)
            ccall(:jl_dump_llvm_opt, Nothing, (Ptr{Nothing},), llvm_io.handle)
            try
                $commands
            finally
                ccall(:jl_dump_emitted_mi_name, Nothing, (Ptr{Nothing},), C_NULL)
                ccall(:jl_dump_llvm_opt, Nothing, (Ptr{Nothing},), C_NULL)
                close(func_io)
                close(llvm_io)
            end
        end
        exit()
    end)
    wait(process)
    println("done.")
    nothing
end
