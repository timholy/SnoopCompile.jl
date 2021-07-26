"""
"""
macro snoop_all(fname_prefix, commands)
    snoopl_csv_f, snoopl_yaml_f, snoopc_csv_f =
        "$fname_prefix.snoopl.csv", "$fname_prefix.snoopl.yaml", "$fname_prefix.snoopc.csv"
    outsym = gensym(:output)
    esc(quote
        @snoopc pspawn=false $snoopc_csv_f begin
            @snoopl pspawn=false $snoopl_csv_f $snoopl_yaml_f begin
                global $outsym = @snoopi_deep begin
                    @eval $commands
                end
            end
        end;
        $outsym, $snoopl_csv_f, $snoopl_yaml_f, $snoopc_csv_f
    end)
end