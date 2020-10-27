# TODO: Add `@snoopc` into the mix
macro snoop_all(csv_f, yaml_f, commands)
    esc(quote
        v = @snoopi_deep begin
            @snoopl pspawn=false $csv_f $yaml_f begin
                $commands
            end
        end;
        v
    end)
end