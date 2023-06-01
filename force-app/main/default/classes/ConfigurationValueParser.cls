public with sharing class ConfigurationValueParser {
    public class Input {
        @InvocableVariable(label='Attribute Name')
        public String attr;
        @InvocableVariable(label='Configuration Values')
        public List<Configuration_Value__c> cfgVals;
    }
    public class Output {
        @InvocableVariable(label='Text Value')
        public String textVal;
        @InvocableVariable(label='Number Value')
        public Decimal numberVal;
        @InvocableVariable(label='Boolean Value')
        public Boolean booleanVal;
    }
    @InvocableMethod(label='Get Configuration Value')
    public static List<Output> getConfigVal(List<Input> inputs) {
        List<Output> outputs = new List<Output>();
        for (Input input : inputs) {
            Output out = new Output();
            for (Configuration_Value__c cfgVal : input.cfgVals) {
                if(cfgVal.Attribute_Name__c == input.attr) {
                    switch on cfgVal.Data_Type__c {
                        when 'Text' {
                            out.textVal = cfgVal.Text_Value__c;
                        }
                        when 'Number' {
                            out.numberVal = cfgVal.Number_Value__c;
                        }
                        when 'Boolean' {
                            out.booleanVal = cfgVal.Boolean_Value__c;
                        }
                    }
                }
            }
            outputs.add(out);
        }
        return outputs;
    }
}