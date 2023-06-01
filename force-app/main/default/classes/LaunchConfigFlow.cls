public with sharing class LaunchConfigFlow {
    public class ConfigFlowInput {
        @InvocableParameter(name='Configuration Values')
        List<Configuration_Value__c> cfgVals;
        @InvocableParameter(name='Bundle Product Id')
        Id prodId;
    }
    @InvocableMethod(name='Launch Configuration Flow')
    public static List<ConfigFlowOutput> LaunchConfigFlow(List<ConfigFlowInput> inputs) {
        for (ConfigFlowInput input : inputs) {
            Product2 prod = [SELECT Id, Config_Flow__c FROM Product2 WHERE Id = :input.prodId];
            Map<String,Object> flowInputs = new Map<String,Object>();
            for (Configuration_Value__c cfgVal : input.cfgVals) {
                Object val;
                switch on cfgVal.Data_Type__c {
                    when 'Text' {
                        val = cfgVal.Text_Value__c;
                    }
                    when 'Number' {
                        val = cfgVal.Number_Value__c;
                    }
                    when 'Boolean' {
                        val = cfgVal.Boolean_Value__c;
                    }
                }
                flowInputs.set(cfgVal.Attribute_Name__c, val);
            }
            Flow.Interview.createInterview(prod.Configuration_Flow__c, flowInputs).start();
        }
    }
}