trigger ContentVersionAfterInsert on ContentVersion (after insert) {
    for (ContentVersion cv : Trigger.new) {
        ContentVersionHandler.updateCustomerAcceptance(cv);
    }
}