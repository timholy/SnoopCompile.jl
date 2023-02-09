export @snoopl

using Serialization

"""
```
@snoopl [jlflags="..."] [pspawn=true] "func_names.csv" "llvm_timings.yaml" begin
    # Commands to execute, either in a new process if pspawn==true, or via eval if false.
end
```
causes the julia compiler to log timing information for LLVM optimization during the
provided commands to the files "func_names.csv" and "llvm_timings.yaml". These files can
be used for the input to `SnoopCompile.read_snoopl("func_names.csv", "llvm_timings.yaml")`.

The logs contain the amount of time spent optimizing each "llvm module", and information
about each module, where a module is a collection of functions being optimized together.

If `pspawn=false`, the commands will be run in the same julia process, via `eval()` in
the current module. This will only report _new_ compilations, that haven't already been
cached in the current julia process, which can be (carefully) used to prune down the
results to only the code you are interested in.
"""
macro snoopl(args...)
    @assert length(args) >= 3 """Usage: @snoopl [args...] "snoopl.csv" "snoopl.yaml" commands"""
    flags, (func_file, llvm_file, commands) = args[1:end-3], args[end-2:end]
    flags = [esc(e) for e in flags]
    return :(snoopl($(esc(func_file)), $(esc(llvm_file)), $(QuoteNode(commands)), $__module__; $(flags...)))
end
macro snoopl(func_file, llvm_file, commands)
    return :(snoopl($(esc(func_file)), $(esc(llvm_file)), $(QuoteNode(commands)), $__module__))
end

function snoopl(func_file, llvm_file, commands, _module; pspawn=true, jlflags="")
    if pspawn
        println("Launching new julia process to run commands...")
    end
    # addprocs will run the unmodified version of julia, so we
    # launch it as a command.
    code_object = """
            using Serialization
            Core.eval(Main, deserialize(IOBuffer(read(stdin))))
            """
    record_and_run_quote = quote
        let func_io = open($func_file, "w"), llvm_io = open($llvm_file, "w")
            ccall(:jl_dump_emitted_mi_name, Nothing, (Ptr{Nothing},), func_io.handle)
            ccall(:jl_dump_llvm_opt, Nothing, (Ptr{Nothing},), llvm_io.handle)
            try
                @eval $commands
            finally
                ccall(:jl_dump_emitted_mi_name, Nothing, (Ptr{Nothing},), C_NULL)
                ccall(:jl_dump_llvm_opt, Nothing, (Ptr{Nothing},), C_NULL)
                close(func_io)
                close(llvm_io)
            end
        end
    end

    if pspawn
        process = open(`$(Base.julia_cmd()) $jlflags --eval $code_object`, stdout, write=true)
        @info process
        serialize(process, quote
            $record_and_run_quote
        end)
        close(process)
        wait(process)
        println("done.")
    else
        Core.eval(_module, record_and_run_quote)
    end
    nothing
end
