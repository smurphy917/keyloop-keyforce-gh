public with sharing class AssetTaskBlock {
    public List<AssetManagementProcessTask> tasks;
    private Integer pausedIdx;
    public AssetTaskBlock(List<AssetManagementProcessTask> tasks) {
        this.tasks = tasks;
    }
    public Integer process() {
        return this.process(null);
    }
    public Integer process(String namedCredential){
        // System.debug('PROCESSING BLOCK OF ' + this.tasks.size() + ' TASKS');
        Integer successCount = 0;
        List<Exception> errors = new List<Exception>();
        Integer cpuLimit = Limits.getLimitCpuTime();
        Integer startIdx = 0;
        if(this.pausedIdx != null) {
            // System.debug('BLOCK PAUSED');
            startIdx = this.pausedIdx;
        }
        for (Integer idx = startIdx; idx < this.tasks.size(); idx++) {
            Decimal plannedExecutionTime = (idx / this.tasks.size()) * (0.75 * cpuLimit);
            Decimal cpuTimeBuffer = cpuLimit * 0.25;
            if(!Test.isRunningTest() && Limits.getCpuTime() > (plannedExecutionTime + cpuTimeBuffer)) {
                // CPU time looks to be ahead of planned time by an amount that exceeds 8% of the overall limit
                throw new AssetTaskBlockException('CPU comfort level exceeded.\nBlock: \n' + JSON.serialize(this));
            }
            try {
                successCount += this.tasks[idx].process(namedCredential);
            } catch (AssetManagementProcessTask.RequestLimitExceededException e) {
                this.pausedIdx = idx;
                throw e;
            }
        }
        return successCount;
    }
    private class AssetTaskBlockException extends Exception {}
}