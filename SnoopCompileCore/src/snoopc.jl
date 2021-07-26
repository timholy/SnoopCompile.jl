export @snoopc

using Serialization

"""
```
@snoopc [pspawn=true] [String["<julia_flags...>"]] "compiledata.csv" begin
    # Commands to execute, either in a new process if pspawn==true, or via eval if false.
end
```
causes the julia compiler to log all functions compiled in the course
of executing the commands to the file "compiledata.csv". This file
can be used for the input to `SnoopCompile.read`.

Julia flags can optionally be passed as a string or an array of strings, which will be set
on the newly spawned julia process if `pspawn=true`. If `pspawn=false`, setting
`julia_flags` will be ignored.

If `pspawn=false`, the commands will be run in the same julia process, via `eval()` in
the current module. This will only report _new_ compilations, that haven't already been
cached in the current julia process, which can be (carefully) used to prune down the
results to only the code you are interested in.
"""
macro snoopc(args...)
    @assert 4 >= length(args) >= 2 """Usage: @snoopl [args...] "snoopl.csv" "snoopl.yaml" commands"""
    flags, (filename, commands) = args[1:end-2], args[end-1:end]
    pspawn_expr, julia_flags = begin
        if length(flags) == 2
            flags[1], flags[2]
        elseif flags[1].head == :(=) && flags[1].args[1] == :pspawn
            flags[1], String[]
        else
            :(pspawn=false), flags[1]
        end
    end
    return :(snoopc($(esc(julia_flags)), $(esc(filename)), $(QuoteNode(commands)), $__module__; $(esc(pspawn_expr))))
end
macro snoopc(filename, commands)
    return :(snoopc(String[], $(esc(filename)), $(QuoteNode(commands))))
end

function snoopc(flags, filename, commands, _module=nothing; pspawn=true)
    if pspawn
        println("Launching new julia process to run commands...")
    end
    # addprocs will run the unmodified version of julia, so we
    # launch it as a command.
    code_object = """
            using Serialization
            while !eof(stdin)
                Core.eval(Main, deserialize(stdin))
            end
            """
    record_and_run_quote = quote
        let io = open($filename, "w")
            ccall(:jl_dump_compiles, Nothing, (Ptr{Nothing},), io.handle)
            try
                $commands
            finally
                ccall(:jl_dump_compiles, Nothing, (Ptr{Nothing},), C_NULL)
                close(io)
            end
        end
    end

    if pspawn
        process = open(`$(Base.julia_cmd()) $flags --eval $code_object`, stdout, write=true)
        serialize(process, quote
            $record_and_run_quote
            exit()
        end)
        wait(process)
        println("done.")
    else
        Core.eval(_module, record_and_run_quote)
    end
    nothing
end
