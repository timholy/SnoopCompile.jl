# TODO: Add `@snoopc` into the mix
macro snoop_all(snoopl_csv_f, snoopl_yaml_f, snoopc_csv_f, commands)
    outsym = gensym(:output)
    esc(quote
        @snoopc pspawn=false $snoopc_csv_f begin
            @snoopl pspawn=false $snoopl_csv_f $snoopl_yaml_f begin
                global outsym = @snoopi_deep begin
                    @eval $commands
                end
            end
        end;
        outsym
    end)
end