public with sharing class ActionRunAfterJob {
    public class InvocableParameter {
        @InvocableVariable(label='Apex Job Id')
        public String jobId;
        @InvocableVariable(label='Flow API Name')
        public String flowApiName;
        @InvocableVariable(label='Flow Input Names')
        public List<String> flowInputNames;
        @InvocableVariable(label='Flow Input Values')
        public List<String> flowInputValues;
    }
    @InvocableMethod(label='Run Flow After Job')
    public static void InvocableRunFlowAfterJob(List<InvocableParameter> parameters) {
        for (InvocableParameter p : parameters) {
            Map<String,String> flowInputs = new Map<String,String>();
            for (Integer i = 0; i < p.flowInputNames.size(); i++) {
                flowInputs.put(p.flowInputNames[i], p.flowInputValues[i]);
            }
            System.enqueueJob(new TaskPoller(p.jobId, new JobHandler(p.flowApiName, flowInputs)), 1);
        }
    }
    public class JobHandler implements TaskPoller.TaskHandler {
        String flowName;
        Map<String,String> flowInputs;
        public JobHandler(String flowName, Map<String,String> flowInputs) {
            this.flowName = flowName;
            this.flowInputs = flowInputs;
        }
        public void onCompleted() {
            Flow.Interview.createInterview(this.flowName, this.flowInputs).start();
        }
        public void onFailed(String error) {
            throw new JobFailedException(error);
        }
    }
    public class JobFailedException extends Exception{}
}