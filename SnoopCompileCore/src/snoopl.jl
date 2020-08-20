export @snoopl

using Serialization

"""
```
@snoopl "func_info.csv" "llvm_timings.csv" begin
    # Commands to execute, in a new process
end
```
causes the julia compiler to emit the LLVM optimization times for
of executing the commands to the file "compiledata.csv". This file
can be used for the input to `snooplompile.read`.
"""
macro snoopl(flags, func_file, llvm_file, commands)
    return :(snoopl($(esc(flags)), $(esc(func_file)), $(esc(llvm_file)), $(QuoteNode(commands))))
end
macro snoopl(func_file, llvm_file, commands)
    return :(snoopl(String[], $(esc(func_file)), $(esc(llvm_file)), $(QuoteNode(commands))))
end

function snoopl(flags, func_file, llvm_file, commands)
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
