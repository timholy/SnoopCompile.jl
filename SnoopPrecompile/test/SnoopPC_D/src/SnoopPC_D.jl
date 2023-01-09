module SnoopPC_D

using SnoopPrecompile

@precompile_setup begin
    @precompile_all_calls begin
        global workload_ran = true
    end
end

end # module SnoopPC_D
