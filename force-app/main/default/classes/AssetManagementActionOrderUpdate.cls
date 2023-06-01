public with sharing class AssetManagementActionOrderUpdate {
    public class InvocableParameter {
        @InvocableVariable(label='Order Id' required=true)
        public Id orderId;
        @InvocableVariable(label='Named Credential' description='Key of a Named Credential to be used for internal REST calls')
        public String namedCredential;
    }

    @InvocableMethod(label='Update Assets on Order Update' description='Update status and other asset details when an order is updated' category='Asset Management')
    public static void InvocableUpdateOrder(List<InvocableParameter> parameters) {
        for (InvocableParameter p : parameters) {
            Serenity.namedCredential = p.namedCredential;
            // Serenity.OrderUpdate(p.orderId);
            Serenity.AsyncRequest(Serenity.AsyncAction.OrderUpdate, p.orderId, null);
        }
    }
}