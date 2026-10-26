# Run with: MIX_ENV=test mix run --no-start scripts/validate_tck_expressions.exs
{:ok, _applications} = Application.ensure_all_started(:boxic_dmn)

groups = Boxic.DMN.TCK.profile_groups("dmn", "implemented")

paths =
  Boxic.DMN.TCK.Loader.load_all()
  |> Enum.filter(&(&1.group in groups))
  |> Enum.map(& &1.model_path)
  |> Enum.uniq()

failures =
  Enum.flat_map(paths, fn path ->
    result =
      with {:ok, model} <- Boxic.DMN.TCK.ModelLoader.load(path),
           do: Boxic.DMN.validate(model, for: :evaluation)

    case result do
      :ok -> []
      {:error, diagnostics} -> [{Path.relative_to_cwd(path), diagnostics}]
    end
  end)

revision = File.read!(Path.expand("../vendor/dmn-tck/PINNED_COMMIT", __DIR__)) |> String.trim()
IO.puts("DMN TCK revision: #{revision}")
IO.puts("Static preflight: #{length(paths) - length(failures)}/#{length(paths)} models passed")

if failures != [] do
  Enum.each(failures, fn failure -> IO.puts(inspect(failure, limit: :infinity)) end)
  System.halt(1)
end
