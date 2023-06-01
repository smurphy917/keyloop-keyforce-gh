public without sharing class AssetManagementProcessTask {
    public enum TaskType {
        CALLOUT,
        DML
    }
    public static Boolean skipDML = false;
    public static Http http = new Http();
    public TaskType type;
    // for CALLOUT type
    public Tranquility.SerializableRequest request;
    // for DML type
    public List<SObject> records;
    public PWUtils.DMLOperation op;

    // Hooks
    PreProcessingHook preHook;
    PostProcessingHook postHook;

    // Context
    // Map<String, Object> context = new Map<String, Object>();

    // public static Map<String, Object> processData = new Map<String, Object>();

    /*
    public AssetManagementProcessTask(HttpRequest request) {
        this.type = TaskType.CALLOUT;
        this.request = new Tranquility.SerializableRequest(request);
    }
    */

    public AssetManagementProcessTask(Tranquility.SerializableRequest request) {
        this.type = TaskType.CALLOUT;
        this.request = request;
    }

    public AssetManagementProcessTask(PWUtils.DMLOperation op, SObject record){
        this.type = TaskType.DML;
        this.op = op;
        this.records = new List<SObject>();
        this.records.add(record);
    }
    
    public AssetManagementProcessTask(PWUtils.DMLOperation op, List<SObject> records){
        this.type = TaskType.DML;
        this.op = op;
        this.records = records;
    }
    // public void addContext(String key, Object val) {
    //     this.context.put(key, val);
    // }
    // public Object getContext (String key) {
    //     return this.context.get(key);
    // }
    public void before(PreProcessingHook preHook) {
        this.preHook = preHook;
    }
    public void after(PostProcessingHook postHook) {
        this.postHook = postHook;
    }
    public Integer process() {
        return this.process(null);
    }
    public Integer process(String namedCredential) {
        System.debug('*** PROCESSING TASK ***\n' + JSON.serialize(this));
        Result result;
        Integer successCount = 0;
        String[] errors = new String[]{};
        if(this.preHook != null) {
            this.preHook.process(this);
        }
        switch on this.type {
            when CALLOUT {
                HttpResponse response = http.send(this.request.toRequest(namedCredential));
                Integer statusCode = response.getStatusCode();
                if(statusCode >= 200 && statusCode < 300) {
                    result = new Result(this, response);
                    successCount = 1;
                } else {
                    List<ErrorResponse> errResponses = (List<ErrorResponse>) JSON.deserialize(response.getBody(), List<ErrorResponse>.class);
                    if(errResponses[0].errorCode == 'REQUEST_LIMIT_EXCEEDED') {
                        throw new RequestLimitExceededException();
                    }
                    throw new TaskException('Server returned error: ' + response.getBody() + '\nEndpoint: ' + this.request.endpoint + '\nRequest Body: ' + this.request.body);
                }
            }
            when DML {
                successCount = 0;
                if(skipDML){
                    System.debug('SKIPPING DML OPERATION [' + this.op.name() + '] on records: ' + this.records);
                    if(Test.isRunningTest()) {
                        PWUtils.validateDML((PWUtils.DMLOperation) this.op, this.records);
                        System.debug('RECORDS: ' + JSON.serialize(this.records));
                    }
                } else {
                    Database.SaveResult[] dbResults;
                    switch on this.op {
                        when DML_UPDATE {
                            dbResults = Database.update(this.records, false);
                        }
                        when DML_INSERT {
                            dbresults = Database.insert(this.records, false);
                        }
                        // when DML_DELETE {
                        //     Database.delete(this.records, false);
                        //     // TODO: annoyingly, there's no common class ancestor of SaveResult and Delete result so, since we aren't really doing any deletions anywya, just keeping this simple for now and not parsing delete results.
                        // }
                    }
                    Integer recordIdx = 0;
                    for (Database.SaveResult dbResult : dbResults) {
                        if(dbResult.isSuccess()) {
                            successCount++;
                        } else {
                            for (Database.Error dbError : dbResult.getErrors()) {
                                errors.add(
                                    'RECORD: ' + JSON.serialize(this.records[recordIdx]) + '\n' +
                                    'FIELDS:' + String.join(dbError.getFields(),',') + '\n' +
                                    'MESSAGE:' + dbError.getMessage() + '\n' + 
                                    'STATUS_CODE:' + dbError.getStatusCode() + '\n'
                                );
                            }
                        }
                        recordIdx++;
                    }
                }
                result = new Result(this);
            }
        }
        if(this.postHook != null) {
            this.postHook.process(this, result);
        }
        if(errors.size() > 0) {
            TaskException err = new TaskException('DML ERROR');
            err.successCount = successCount;
            err.errors = errors;
            throw err;
        } else {
            return successCount;
        }
        // System.debug('UPDATED PROCESS DATA:');
        // System.debug(JSON.serialize(processData));
        // return processData;
    }

    public class Result {
        public AssetManagementProcessTask task;
        public HttpResponse response;
        public Result (AssetManagementProcessTask task) {
            this.task = task;
        }
        public Result (AssetManagementProcessTask task, HttpResponse response) {
            this.task = task;
            this.response = response;
        }
    }

    public class ErrorResponse {
        public String errorCode;
        public String errorMessage;
    }

    /*
    public static List<AssetManagementProcessTask> batchify (List<AssetManagementProcessTask> unbatched) {
        List<AssetManagementProcessTask> unbatchable = new List<AssetManagementProcessTask>();
        List<AssetManagementProcessTask> rawTasks = new List<AssetManagementProcessTask>();
        List<BatchSubrequest> requests = new List<BatchSubrequest>();
        List<PostProcessingHook> postHooks = new List<PostProcessingHook>();
        for (AssetManagementProcessTask task : unbatched) {
            if(task.type == TaskType.CALLOUT) {
                requests.add(new BatchSubrequest(task.request.toRequest()));
                rawTasks.add(task);
                postHooks.add(task.postHook);
            } else {
                unbatchable.add(task);
            }
        }
        List<AssetManagementProcessTask> batched = new List<AssetManagementProcessTask>();
        if(requests.size() > 0) {
            Map<String,List<BatchSubrequest>> batchBody = new Map<String,List<BatchSubrequest>>();
            batchBody.put('batchRequests', requests);
            HttpRequest batchRequest = new HttpRequest();
            batchRequest.setMethod('POST');
            batchRequest.setEndpoint('callout:Salesforce/services/data/v56.0/composite/batch');
            batchRequest.setBody(JSON.serialize(batchBody));
            batchRequest.setHeader('Content-Type', 'application/json');
            batchRequest.setHeader('Accept', 'application/json');
            AssetManagementProcessTask batchTask = new AssetManagementProcessTask(batchRequest);
            batchTask.after(new PostBatchHook(rawTasks, postHooks));
            batched = new List<AssetManagementProcessTask>{
                batchTask
            };
        }
        batched.addAll(unbatchable);
        return batched;
    }

    public class BatchSubrequest {
        public String method;
        public String url;
        public Object richInput;
        // public String referenceId;

        public BatchSubRequest(){}
        public BatchSubRequest(HttpRequest req) {
            this.method = req.getMethod();
            this.url = req.getEndpoint();
            this.richInput = JSON.deserializeUntyped(req.getBody());
            // this.referenceId = referenceId;
            if(this.url.startsWith('callout:Salesforce')) {
                this.url = this.url.replace('callout:Salesforce', '');
            }
        }
    }
    public class BatchResponse {
        Boolean hasErrors;
        List<BatchSubResponse> results;
    }
    public class BatchSubResponse {
        Integer statusCode;
        String result;
    }
    */

    public interface PreProcessingHook {
        void process(AssetManagementProcessTask task);
    }
    public interface PostProcessingHook {
        void process(AssetManagementProcessTask task, Result result);
    }

    /*
    public class PostBatchHook implements PostProcessingHook {
        List<PostProcessingHook> postHooks;
        List<AssetManagementProcessTask> tasks;
        public PostBatchHook(List<AssetManagementProcessTask> tasks, List<PostProcessingHook> postHooks){
            this.postHooks = postHooks;
            this.tasks = tasks;
        }
        public void process(AssetManagementProcessTask task, Result result) {
            System.debug('BATCH RESPONSE:\n' + result.response.getBody());
            BatchResponse resp = (BatchResponse) JSON.deserialize(result.response.getBody(), BatchResponse.class);
            for (Integer i = 0; i < resp.results.size(); i++) {
                HttpResponse mockResp = new HttpResponse();
                mockResp.setStatusCode(resp.results[i].statusCode);
                mockResp.setbody(resp.results[i].result);
                this.postHooks[i].process(this.tasks[i], new Result(task, mockResp));
            }
        }
    }
    */

    public override String toString() {
        return JSON.serialize(this);
    }

    public class TaskException extends Exception {
        public Integer successCount = 0;
        public String[] errors = new String[]{};
        public override String getMessage() {
            return super.getMessage() + '\n' + String.join(this.errors, '\n');
        }
    }

    public class RequestLimitExceededException extends Exception {
    }
}