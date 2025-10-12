defmodule GitFoil.Helpers.OutputMessages do
  @moduledoc """
  Shared output messages for GitFoil commands.

  This module provides consistent, transparent messaging across all commands.
  Key principle: ALWAYS show both git-foil and git commands for transparency.
  """

  @doc """
  Standard "next step - commit" message.

  Always shows both git-foil and git commands for transparency.
  """
  def next_step_commit(message \\ "Changes") do
    """
    💡  Next step - commit your changes:
          git-foil commit

       Or use git directly:
          git add .
          git commit -m "#{message}"
    """
  end

  @doc """
  "Next step - commit" message for a specific file.

  Always shows both git-foil and git commands for transparency.
  """
  def next_step_commit_file(file, message) do
    """
    💡  Next step - commit your changes:
          git-foil commit

       Or use git directly:
          git add #{file}
          git commit -m "#{message}"
    """
  end

  @doc """
  Note about working directory files remaining plaintext.

  This should only be shown ONCE during init, not repeated in every command.
  """
  def encryption_active_note do
    """
    📌 Files in your working directory remain plaintext.
       Only versions stored in Git are encrypted.
    """
  end
end
