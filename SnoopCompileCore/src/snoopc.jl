export @snoopc

using Serialization

"""
```
@snoopc "compiledata.csv" begin
    # Commands to execute, in a new process
end
```
causes the julia compiler to log all functions compiled in the course
of executing the commands to the file "compiledata.csv". This file
can be used for the input to `SnoopCompile.read`.
"""
macro snoopc(flags, filename, commands)
    return :(snoopc($(esc(flags)), $(esc(filename)), $(QuoteNode(commands))))
end
macro snoopc(filename, commands)
    return :(snoopc(String[], $(esc(filename)), $(QuoteNode(commands))))
end

function snoopc(flags, filename, commands)
    println("Launching new julia process to run commands...")
    # addprocs will run the unmodified version of julia, so we
    # launch it as a command.
    code_object = """
            using Serialization
            while !eof(stdin)
                Core.eval(Main, deserialize(stdin))
            end
            """
    process = open(`$(Base.julia_cmd()) $flags --eval $code_object`, stdout, write=true)
    serialize(process, quote
        let io = open($filename, "w")
            ccall(:jl_dump_compiles, Nothing, (Ptr{Nothing},), io.handle)
            try
                $commands
            finally
                ccall(:jl_dump_compiles, Nothing, (Ptr{Nothing},), C_NULL)
                close(io)
            end
        end
        exit()
    end)
    wait(process)
    println("done.")
    nothing
end
