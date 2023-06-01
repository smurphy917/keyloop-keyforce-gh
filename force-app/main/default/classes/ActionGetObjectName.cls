public with sharing class ActionGetObjectName {
    
    public class InvocableParameter {
        @InvocableVariable(label='Object Id')
        public String objId;
    }
    @InvocableMethod(label='Get Object Name' description='Return sobject API name for id value' category='Utilities')
    public static List<InvocableResult> InvocableGetObjectName(List<InvocableParameter> params) {
        List<InvocableResult> results = new List<InvocableResult>();
        for (InvocableParameter param : params) {
            results.add(
                new InvocableResult(Id.valueOf(param.objId).getSObjectType().getDescribe().getName())
            );
        }
        return results;
    }
    
    public class InvocableResult {
        @InvocableVariable(label='Object Name')
        public String objName;
        public InvocableResult(String objName){
            this.objName = objName;
        }
    }
}