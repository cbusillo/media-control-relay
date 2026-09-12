# Control-surface integration

Companion owns Loupedeck pages, encoders, macros and Apple TV controls. MCR does
not install or configure control-surface software and is not required for those
Apple TV actions. See [product scope](product-scope.md) for the migration.

MCR retains the optional active-output volume actuators:

- `media-control-relay://control/volume/up`
- `media-control-relay://control/volume/down`
- `media-control-relay://control/volume/mute`

These retain the same route matching, permission and command bounds as before.
They do not provide a general-purpose remote API. All old
`media-control-relay://remote/...` URLs are rejected; replace them with the
Companion module actions before adopting this MCR build. Profiles and bindings
are user-managed and are never rewritten by the MCR app.
