@isTest
public class TaskPollerTest {
    @isTest
    public static void test() {
        List<Id> jobIds;
        TaskHandler handler = new TaskHandler();
        try {
            Test.startTest();
            System.enqueueJob(new QueueFailure(),1);
            System.enqueueJob(new QueueSuccess(),1);
            jobIds = Test.enqueueBatchJobs(2);
            for (Id jobId : jobIds) {
                System.enqueueJob(new TaskPoller(jobId,handler));
            }
            Test.enqueueBatchJobs(10);
            Test.stopTest();
        } catch (AsyncException e) {

        }
    }
    public class QueueFailure implements Queueable {
        public void execute(QueueableContext ctx) {
            throw new AsyncException('error');
        }
    }
    public class QueueSuccess implements Queueable {
        public void execute(QueueableContext ctx) {
            // do nothing
        }
    }
    public class TaskHandler implements TaskPoller.TaskHandler {
        Integer successCount = 0;
        Integer failureCount = 0;
        String error;
        public void onCompleted() {
            this.successCount++;
        }
        public void onFailed(String error) {
            this.failureCount++;
            this.error = error;
        }
    }
}