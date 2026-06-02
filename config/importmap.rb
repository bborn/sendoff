# Pins for the Sendoff admin UI. Appended onto the host app's importmap by
# Sendoff::Engine. We pin Turbo + Stimulus explicitly (their gems ship the
# compiled assets, served via the host's asset pipeline) so the UI works even
# when the host app hasn't pinned them itself.
pin "@hotwired/turbo-rails", to: "turbo.min.js", preload: true
pin "@hotwired/stimulus", to: "stimulus.min.js", preload: true
pin "sortablejs", to: "https://ga.jspm.io/npm:sortablejs@1.15.2/modular/sortable.esm.js"

pin "sendoff/application", to: "sendoff/application.js", preload: true
pin_all_from Sendoff::Engine.root.join("app/javascript/sendoff/controllers"),
             under: "sendoff/controllers", to: "sendoff/controllers"
