# Debugging Shortcuts

Find out why a shortcut did — or didn't — fire.

## Overview

A shortcut that does nothing is silent, and there are several reasons it might
be: the context isn't active, a text field has focus, the key is auto-repeating
and the action opted out, a global binding shadows the local one, or another
context won first.

Two Core APIs answer those questions. Neither stores anything — keep whatever
history you need on the observing side.

## The activation stack

``ShortcutRegistry/activationSnapshot`` is the live stack in the order the router
consults it. This matters when two active contexts bind the same trigger:
dispatch is innermost-first with early termination, so stack position decides the
winner.

``ShortcutRegistry/activeBindings()`` collapses the same information to a `Set`
of context ids, which discards both the ordering and the fact that one context
can be activated twice. Use the snapshot when precedence is the question.

```swift
for entry in registry.activationSnapshot.innermostFirst {
    print(entry.contextID, entry.activationID)
}
```

An empty snapshot is itself the answer: with no context active the router isn't
listening at all.

## Per-keystroke outcomes

``ShortcutRegistry/debugEvents`` reports what became of each key event. Set
``ShortcutRegistry/isDebugRecording`` to `true` to start it — subscribing alone
is not enough, and while it's `false` the event path pays a single optional test
per keystroke.

```swift
registry.isDebugRecording = true
registry.debugEvents
    .sink { event in
        switch event.outcome {
        case let .dispatched(ref, depth):
            print("\(event.pressed.displayString) → \(ref.actionID) at depth \(depth)")
        case let .advanced(ref):
            print("chord in progress: \(ref.actionID)")
        case let .suppressedKeyRepeat(ref):
            print("repeat suppressed: \(ref.actionID)")
        case .noMatch:
            print("nothing matched \(event.pressed.displayString)")
        }
    }
    .store(in: &cancellables)
```

Turn it off when you're done — the flag is what gates emission.

## What isn't covered

- **Keystrokes surrendered to a focused text field report `noMatch`.** The focus
  gate lives in ShortcutField and returns the same result as a genuine non-match,
  so the two can't be told apart from here.
- **Global (Carbon) hotkeys emit nothing.** They're delivered by the OS straight
  to the context and never pass through the router.
  ``ShortcutRegistry/actionFired`` does see them.
- **Key events only.** Continuous scroll and gesture shortcuts aren't reported.

## Topics

### Debug Types

- ``ShortcutDebugEvent``
- ``ActivationSnapshot``
