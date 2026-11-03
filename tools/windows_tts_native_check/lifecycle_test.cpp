#include "../../windows/runner/neura_tts_lifecycle.h"

#include <iostream>
#include <stdexcept>

int checks = 0;
void Require(bool value) {
  ++checks;
  if (!value) throw std::runtime_error("Synthetic speech lifecycle check failed");
}

int main() {
  NeuraTtsLifecycle state;
  Require(state.request() == 0 && state.state() == "idle");
  Require(!state.Start(0, 1) && !state.Start(-1, 1) && !state.Start(1, 0));
  Require(!state.Owns(0) && !state.Owns(10));  // Nothing speaking yet.
  Require(state.Start(1, 10));
  Require(state.Owns(10) && !state.Owns(9) && !state.Owns(0));
  Require(!state.CanStart(2));
  state.End(1, 9);
  Require(state.state() == "speaking");
  state.Cancel();
  Require(!state.Owns(10));  // A cancelled stream's late visemes are ignored.
  state.End(1, 10);
  Require(state.state() == "cancelled");
  Require(!state.Start(1, 11));
  Require(state.Start(2, 10));  // Native stream numbers may be reused.
  state.End(1, 10);  // Old owner completion after replacement starts.
  Require(state.state() == "speaking" && state.request() == 2);
  state.End(2, 10);
  Require(state.state() == "completed");
  Require(!state.Owns(10));  // Completed streams no longer own events.
  state.End(2, 10);  // Duplicate is idempotent.
  Require(state.state() == "completed");
  state.Cancel();
  Require(state.Start(3, 12));
  state.Fail();
  state.Cancel();
  Require(state.state() == "failed");
  Require(!state.Start(4, 13));
  Require(NeuraTtsPitchText(L"<&>\"'", 0) ==
          L"<pitch absmiddle=\"0\">&lt;&amp;&gt;&quot;&apos;</pitch>");
  Require(NeuraTtsPitchText(L"<audio src='file:///synthetic'/>", -10).find(
              L"<audio") == std::wstring::npos);
  Require(NeuraTtsPitchText(L"synthetic", 10) ==
          L"<pitch absmiddle=\"10\">synthetic</pitch>");
  std::cout << checks << " native ownership/escaping assertions passed; no speech executed\n";
}
