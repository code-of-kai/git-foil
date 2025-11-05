defmodule GitFoil.CLI.PasswordInput do
  @moduledoc """
  High-level helpers for reading passwords across interactive and
  non-interactive flows. Wraps `GitFoil.CLI.PasswordPrompt` and enforces
  consistent error handling/exit codes.
  """

  alias GitFoil.CLI.PasswordPrompt
  alias GitFoil.CLI.PasswordPrompt.PromptError
  alias GitFoil.Helpers.UIPrompts

  @typedoc "Standard error tuple used by password input helpers."
  @type error :: {:error, {exit_code :: integer(), message :: String.t()}}

  @doc """
  Reads a new password (optionally with confirmation).

  Options:
    * `:password_source` – `:tty` (default), `:stdin`, `{:file, path}`, `{:fd, fd}`
    * `:password_no_confirm` – skip confirmation (default: `false`)
    * `:confirm` – require confirmation when interactive (default: `true`)
    * `:min_length` – minimum length (default: 8)
    * `:allow_empty` – whether empty passwords are allowed (default: false)
    * `:confirm_prompt` – custom confirmation prompt string
    * `:show_requirements` – print password requirements banner when interactive (default: true)
  """
  @spec new_password(String.t(), keyword()) :: {:ok, String.t()} | error()
  def new_password(prompt, opts \\ []) do
    source = Keyword.get(opts, :password_source, :tty)
    confirm? = Keyword.get(opts, :confirm, true)
    no_confirm = Keyword.get(opts, :password_no_confirm, false)
    min_length = Keyword.get(opts, :min_length, 8)
    allow_empty = Keyword.get(opts, :allow_empty, false)

    show_requirements? =
      Keyword.get(opts, :show_requirements, true) && source == :tty && not Keyword.get(opts, :quiet, false)

    if show_requirements?, do: UIPrompts.print_password_requirements()

    prompt_opts =
      [
        confirm: confirm?,
        confirm_prompt: Keyword.get(opts, :confirm_prompt, "Confirm password: "),
        source: source,
        no_confirm: no_confirm,
        min_length: min_length,
        allow_empty: allow_empty
      ]
      |> Enum.reject(fn {_key, value} -> value == nil end)

    case PasswordPrompt.get_password(prompt, prompt_opts) do
      {:ok, password} ->
        {:ok, password}

      {:error, %PromptError{exit_code: code, message: message}} ->
        {:error, {code, message}}

      {:error, reason} ->
        {:error, {2, "Error: Password prompt failed: #{PasswordPrompt.format_error(reason)}"}}
    end
  end

  @doc """
  Reads an existing password (no confirmation).

  Options:
    * `:password_source` – `:tty`, `:stdin`, `{:file, path}`, `{:fd, fd}`
    * `:allow_empty` – allow empty strings (default: true)
  """
  @spec existing_password(String.t(), keyword()) :: {:ok, String.t()} | error()
  def existing_password(prompt, opts \\ []) do
    source = Keyword.get(opts, :password_source, :tty)
    allow_empty = Keyword.get(opts, :allow_empty, true)

    prompt_opts =
      [
        source: source,
        allow_empty: allow_empty
      ]
      |> Enum.reject(fn {_key, value} -> value == nil end)

    case PasswordPrompt.get_existing_password(prompt, prompt_opts) do
      {:ok, password} ->
        {:ok, password}

      {:error, %PromptError{exit_code: code, message: message}} ->
        {:error, {code, message}}

      {:error, reason} ->
        {:error, {2, "Error: Password prompt failed: #{PasswordPrompt.format_error(reason)}"}}
    end
  end
end
