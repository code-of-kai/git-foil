defmodule GitFoil.TestSupport.TempRepo do
  @moduledoc false

  @doc """
  Creates a fresh temporary Git repository and returns its path.
  """
  def create! do
    base = System.tmp_dir!()
    path = Path.join(base, "gitfoil_test_" <> unique_suffix())
    File.rm_rf!(path)
    File.mkdir_p!(path)
    {_, 0} = System.cmd("git", ["init"], cd: path)
    path
  end

  defp unique_suffix do
    System.unique_integer([:positive])
    |> Integer.to_string()
  end
end
