import { application } from "sendoff/controllers/application"

import ClipboardController from "sendoff/controllers/clipboard_controller"
import ToastsController from "sendoff/controllers/toasts_controller"
import KanbanController from "sendoff/controllers/kanban_controller"
import ModalController from "sendoff/controllers/modal_controller"
import PanelController from "sendoff/controllers/panel_controller"
import SendingCountdownController from "sendoff/controllers/sending_countdown_controller"

application.register("clipboard", ClipboardController)
application.register("toasts", ToastsController)
application.register("kanban", KanbanController)
application.register("modal", ModalController)
application.register("panel", PanelController)
application.register("sending-countdown", SendingCountdownController)
