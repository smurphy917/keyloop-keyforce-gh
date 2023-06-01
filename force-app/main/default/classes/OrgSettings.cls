public with sharing class OrgSettings {
  public static Boolean LogikEnabled {
    get {
      return Type.forName('LGK__ConfigurationBOM__c') != null;
    }
  }
  public static Boolean BillingEnabled {
    get {
      // return UserInfo.isCurrentUserLicensed('blng');
      return Type.forName('blng__Invoice__c') != null;
    }
  }
}