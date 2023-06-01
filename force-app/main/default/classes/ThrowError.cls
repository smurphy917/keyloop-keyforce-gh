public with sharing class ThrowError {
    public class InvocableParameter {
        @InvocableVariable(label='Error Message')
        public String message;
    }
    @InvocableMethod(label='Throw Exception')
    public static void InvocableThrowException(List<InvocableParameter> parameters) {
        for (InvocableParameter p : parameters) {
            throw new FlowException(p.message);
        }
    }
    public class FlowException extends Exception{}
}