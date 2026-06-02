# Pins for the Sendoff admin UI. These are appended onto the host app's
# importmap by Sendoff::Engine. Turbo and Stimulus themselves are pinned by
# turbo-rails / stimulus-rails.
pin "sendoff/application", to: "sendoff/application.js", preload: true
pin_all_from Sendoff::Engine.root.join("app/javascript/sendoff/controllers"),
             under: "sendoff/controllers", to: "sendoff/controllers"
pin "sortablejs", to: "https://ga.jspm.io/npm:sortablejs@1.15.2/modular/sortable.esm.js"
