public with sharing class ScratchBatch implements Database.Batchable<Id> {
    List<Id> ids;
    public ScratchBatch(List<Id> ids) {
        this.ids = ids;
    }
    public Iterable<Id> start (Database.BatchableContext ctx) {
        return this.ids;
    }
    public void execute (Database.BatchableContext ctx, List<Id> ids) {
        for (Id id : ids) {
            Serenity.AsyncRequest(Serenity.AsyncAction.CancelAll, id);
        }
    }
    public void finish(Database.BatchableContext ctx) {

    }
}