class Agentfocus < Formula
  desc "Click an agent's notification, land in the exact terminal tab"
  homepage "https://github.com/no-hup/agentfocus"
  # TODO: tag v0.1.0, then uncomment url + real sha256 (repo is private today,
  # so `brew install --HEAD no-hup/agentfocus` is the only working path).
  # url "https://github.com/no-hup/agentfocus/archive/refs/tags/v0.1.0.tar.gz"
  # sha256 "PLACEHOLDER"
  license "MIT"
  head "https://github.com/no-hup/agentfocus.git", branch: "main"

  # The helper .app is ad-hoc codesigned at build time; a bottle would ship a
  # cdhash produced on someone else's machine.
  pour_bottle? do
    reason "The helper .app must be ad-hoc codesigned on the machine that runs it."
    satisfy { false }
  end

  depends_on :macos
  depends_on "node" # CLI + hooks are node shebangs

  def install
    odie "Xcode Command Line Tools required: xcode-select --install" unless which("swiftc")

    bin.install "bin/agentfocus"
    prefix.install "hook", "adapters"
    prefix.install "integrations" if File.directory?("integrations") # lands with agent B
    system "./helper/build.sh", libexec # -> libexec/AgentFocus.app
  end

  def caveats
    <<~EOS
      Finish setup (Homebrew is not allowed to write to your home directory):
        agentfocus init

      Re-run `agentfocus init` after every `brew upgrade agentfocus` — it refreshes
      the hooks, the runtime copy in ~/.local/share/agentfocus, and the helper app
      in ~/Applications.
    EOS
  end

  test do
    assert_match "Usage: agentfocus", shell_output("#{bin}/agentfocus 2>&1", 1)
    assert_path_exists libexec/"AgentFocus.app/Contents/MacOS/AgentFocus"
  end
end
