defmodule GitFoil.Helpers.Concurrency do
  @moduledoc """
  Shared helpers for selecting and communicating concurrency settings.

  Provides a small struct that carries the detected core count, our recommended
  worker default, and the selected number of concurrent tasks. Commands can
  apply CLI overrides, prompt the user, and render consistent status output
  without copy/pasting logic.
  """

  @typedoc "Runtime concurrency context shared across commands."
  @type t :: %__MODULE__{
          total: pos_integer(),
          default: pos_integer(),
          selected: pos_integer(),
          source: :auto | :cli | :prompt
        }

  defstruct total: 1, default: 1, selected: 1, source: :auto

  @doc """
  Build a base concurrency context using detected CPU cores and any CLI override.

  Returns `{config, note}`. The `note` communicates if the override was clamped
  to the available core count.
  """
  @spec resolve(keyword()) :: {t(), note :: nil | {:clamped_override, integer()}}
  def resolve(opts \\ []) do
    total = detect_total_cores()
    default = recommended_workers(total)
    override = Keyword.get(opts, :concurrency)

    cond do
      is_integer(override) and override > 0 ->
        selected = clamp(override, total)
        info = if selected != override, do: {:clamped_override, override}, else: nil

        {%__MODULE__{
           total: total,
           default: default,
           selected: selected,
           source: :cli
         }, info}

      true ->
        {%__MODULE__{
           total: total,
           default: default,
           selected: default,
           source: :auto
         }, nil}
    end
  end

  @doc """
  Build a human-friendly description to show before prompting.
  """
  @spec instructions(t(), keyword()) :: String.t()
  def instructions(%__MODULE__{} = config, opts \\ []) do
    task = Keyword.get(opts, :task_label, "GitFoil")
    recommendation =
      if config.default == config.selected do
        "Recommended: #{config.default} #{pluralize_core(config.default)} to leave headroom for Git."
      else
        "Recommended default is #{config.default} #{pluralize_core(config.default)}."
      end

    """
    ⚙️  Detected #{config.total} CPU #{pluralize_core(config.total)} available.
        #{task} can encrypt files in parallel.
        #{recommendation}
    """
    |> String.trim()
  end

  @doc """
  Prompt for a concurrency selection unless the value was provided via CLI.

  Accepts a `prompt_fun` that receives the prompt label and returns user input.
  Returns `{config, note}` where `note` explains when invalid/clamped input
  forces us back to the default.
  """
  @spec prompt(t(), (String.t() -> String.t()), keyword()) ::
          {t(), nil | {:invalid, String.t()} | {:clamped, integer()} | :default}
  def prompt(config, prompt_fun, opts \\ [])

  def prompt(%__MODULE__{source: :cli} = config, _prompt_fun, _opts), do: {config, nil}

  def prompt(%__MODULE__{} = config, prompt_fun, opts) do
    label = Keyword.get(opts, :prompt_label, "Cores")
    default = config.selected

    input =
      prompt_fun.("#{label} [#{default}]: ")
      |> String.trim()

    case parse_concurrency_input(input, config) do
      {:ok, value, info} ->
        new_source =
          case info do
            :user -> :prompt
            {:clamped, _} -> :prompt
            _ -> config.source
          end

        {%{config | selected: value, source: new_source}, info}
    end
  end

  @doc """
  Produce a concise status line describing the selected concurrency.
  """
  @spec summary(t(), keyword()) :: String.t()
  def summary(%__MODULE__{} = config, opts \\ []) do
    prefix = Keyword.get(opts, :prefix, "⚙️ ")

    rationale =
      case config.source do
        :cli -> "from --concurrency flag."
        :prompt -> "per your selection."
        :auto -> "recommended default."
      end

    "#{prefix}Using #{config.selected}/#{config.total} CPU #{pluralize_core(config.selected)} (#{rationale})"
  end

  # ---------------------------------------------------------------------------
  # Internal helpers
  # ---------------------------------------------------------------------------

  defp detect_total_cores do
    [:logical_processors_available, :logical_processors_online, :logical_processors]
    |> Enum.map(&safe_system_info/1)
    |> Enum.find(&valid_core_count?/1)
    |> case do
      nil ->
        schedulers = System.schedulers_online()
        if is_integer(schedulers) and schedulers > 0 do
          schedulers
        else
          1
        end

      count ->
        count
    end
  end

  defp recommended_workers(total) when total <= 1, do: 1
  defp recommended_workers(total), do: max(total - 1, 1)

  defp clamp(value, total) do
    value
    |> max(1)
    |> min(total)
  end

  defp parse_concurrency_input("", %__MODULE__{} = config), do: {:ok, config.selected, :default}

  defp parse_concurrency_input(input, %__MODULE__{} = config) do
    case Integer.parse(input) do
      {value, ""} when value > 0 ->
        clamped = clamp(value, config.total)

        info =
          if clamped == value do
            :user
          else
            {:clamped, value}
          end

        {:ok, clamped, info}

      _ ->
        {:ok, config.selected, {:invalid, input}}
    end
  end

  defp pluralize_core(1), do: "core"
  defp pluralize_core(_), do: "cores"

  defp safe_system_info(tag) do
    :erlang.system_info(tag)
  rescue
    _ -> :unknown
  end

  defp valid_core_count?(value) when is_integer(value) and value > 0, do: true
  defp valid_core_count?(_), do: false
end
