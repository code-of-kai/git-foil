class GitFoil < Formula
  desc "Quantum-resistant Git encryption CLI"
  homepage "https://github.com/code-of-kai/git-foil"
  url "https://github.com/code-of-kai/git-foil/archive/refs/tags/v1.0.1.tar.gz"
  sha256 "2f4c49b6342e92b996ac5e4ef1f931e21e17b0f8dcf07373b305e758d595072e"
  license "MIT"

  depends_on "elixir"
  depends_on "erlang"
  depends_on "rust" => :build

  def install
    ENV["MIX_ENV"] = "prod"

    system "mix", "local.hex", "--force"
    system "mix", "local.rebar", "--force"
    system "mix", "deps.get"
    system "mix", "compile"

    libexec.install "priv"

    system "mix", "escript.build"
    libexec.install "git-foil"

    (bin/"git-foil").write <<~EOS
      #!/bin/bash
      set -euo pipefail
      cd "#{libexec}"
      exec "#{libexec}/git-foil" "$@"
    EOS
    (bin/"git-foil").chmod 0o755
  end

  test do
    assert_match "GitFoil version", shell_output("#{bin}/git-foil version")
  end
end
