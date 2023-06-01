public with sharing class AssetManagementLog {

    private static String cachedNotificationTypeId;
    private static Set<String> cachedRecipientIds;

    public static Id notificationTypeId {
        get {
            String devName = 'Asset_Management_Log';
            if(Test.isRunningTest()){
                devName = 'Asset_Management_Test_Log';
            }
            if(Test.isRunningTest()) {
                return TestUtility.getFakeId(CustomNotificationType.getSObjectType());
            }
            if(cachedNotificationTypeId == null) {
                cachedNotificationTypeId = [SELECT Id, DeveloperName 
                    FROM CustomNotificationType 
                    WHERE DeveloperName=:devName].Id;
            }
            return cachedNotificationTypeId;
        }
    }
    public static Set<String> getRecipientIds() {
        if(cachedRecipientIds == null) {
            cachedRecipientIds = new Set<String>{
                [
                    SELECT Id, DeveloperName 
                    FROM Group 
                    WHERE DeveloperName LIKE 'Contract_Management%' LIMIT 1
                ].Id
            };
        }
        return cachedRecipientIds;
    }
    public static void logBatch(Id sourceId, String sourceAction, Integer successes, Exception[] errors) {
        Asset_Management_Log_Entry__c entry = new Asset_Management_Log_Entry__c(
            Success_Count__c = successes,
            Source_Id__c = sourceId,
            Source_Action__c = sourceAction,
            Has_Error__c = errors.size() > 0
        );
        if(errors.size() > 0) {
            Messaging.CustomNotification notification = new Messaging.CustomNotification();
            // Set the contents for the notification
            notification.setTitle('Asset Management Batch Error');
            String[] body = new String[]{};
            for (Exception e : errors) {
                body.add(e.getMessage());
                body.add(e.getStackTraceString());
            }
            String errorMessage = String.join(body, '\n');
            entry.Error_Details__c = errorMessage.abbreviate(32768);
            notification.setBody(errorMessage);
            
            insert entry;

            // Set the notification type and target
            notification.setNotificationTypeId(notificationTypeId);
            notification.setTargetId(entry.Id);
            // Actually send the notification
            notification.send(getRecipientIds());
            System.debug(LoggingLevel.ERROR, new AssetManagementException(errors));
        } else {
            insert entry;
        }
    }
    public static void logError(Exception e, Id sourceId, String sourceAction) {
        Asset_Management_Log_Entry__c entry = new Asset_Management_Log_Entry__c(
            Success_Count__c = 0,
            Source_Id__c = sourceId,
            Source_Action__c = sourceAction,
            Has_Error__c = true
        );
        Messaging.CustomNotification notification = new Messaging.CustomNotification();
        // Set the contents for the notification
        notification.setTitle('Asset Management Processing Error');
        String errorMessage = e.getMessage() + '\n' + e.getStackTraceString();
        entry.Error_Details__c = errorMessage.abbreviate(32768);
        notification.setBody(errorMessage);
        
        insert entry;

        // Set the notification type and target
        notification.setNotificationTypeId(notificationTypeId);
        notification.setTargetId(entry.Id);
        // Actually send the notification
        if(Test.isRunningTest()) {
            throw e;
        } else {
            notification.send(getRecipientIds());
        }
        System.debug(LoggingLevel.ERROR, e);
        System.debug(LoggingLevel.ERROR, e.getStackTraceString());
    }
    public static void logSuccess(Id sourceId, String sourceAction) {
        Asset_Management_Log_Entry__c entry = new Asset_Management_Log_Entry__c(
            Success_Count__c = 1,
            Source_Id__c = sourceId,
            Source_Action__c = sourceAction,
            Has_Error__c = false
        );
        insert entry;
    }
    public class AssetManagementException extends Exception {
        public AssetManagementException(Exception[] errors) {
            String message = '';
            for (Exception e : errors) {
                message += e.getMessage() + '\n' + e.getStackTraceString() + '\n';
            }
            this.setMessage(message);
        }
    }
}