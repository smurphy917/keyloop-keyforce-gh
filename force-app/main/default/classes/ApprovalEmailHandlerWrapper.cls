global class ApprovalEmailHandlerWrapper implements Messaging.InboundEmailHandler {
    sbaa.ApprovalEmailHandler handler;
    global ApprovalEmailHandlerWrapper() {
        this.handler = new sbaa.ApprovalEmailHandler();
    }
    global Messaging.InboundEmailResult handleInboundEmail(Messaging.InboundEmail email, Messaging.InboundEnvelope envelope) {
        return this.handler.handleInboundEmail(email, envelope);
    }
}