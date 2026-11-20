defmodule Sanctum.Homebrew.SetReportReason do
  @moduledoc "Why someone reported a public homebrew set (`Sanctum.Homebrew.SetReport`)."

  use Ash.Type.Enum,
    values: [
      copyright: "Copyright or IP infringement",
      offensive: "Offensive or abusive content",
      spam: "Spam or not homebrew content",
      other: "Something else"
    ]
end
