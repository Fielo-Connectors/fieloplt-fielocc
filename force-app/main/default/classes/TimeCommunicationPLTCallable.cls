global without sharing class TimeCommunicationPLTCallable implements Callable{

    public static String namespacePrefix {get{
        if (namespacePrefix == null) {
            List<Organization> orgDef = (List<Organization>) Database.query('SELECT NamespacePrefix FROM Organization');
            namespacePrefix = orgDef.isEmpty() ? '' : String.isNotBlank(orgDef.get(0).NamespacePrefix) ? (orgDef.get(0).NamespacePrefix + '__') : '';
        }
        return namespacePrefix;
    } set;}
    
    global Object call(String action, Map<String, Object> args) {
        switch on action {
            when 'processTimeCommunications' {
                return this.processTimeCommunications(args);
            }
            when else {
                throw new FieloPLT.FieloException('Method not implemented');
            }
        }
    }

    public Set<Id> processTimeCommunications(Map<String, Object> args) {
        Set<Id> communicationWithRequests = new Set<Id>();

        Set<Id> recordIds = (Set<Id>)args.get('recordIds');
        Set<Id> communicationIds = (Set<Id>)args.get('communicationIds');

        if(recordIds?.isEmpty() == true ||communicationIds?.isEmpty() == true) {
            throw new FieloPLT.FieloException('recordIds and communicationIds are required');
        }

        try {           
            Set<Id> activeMemberIds = new Set<Id>();
            Set<Id> programIds = new Set<Id>();
            Map<Id,Id> programsByMembers = new Map<Id,Id>();
            for (SObject member : Database.query('SELECT Id,FieloPLT__Program__c  FROM FieloPLT__Member__c ' + 
                'WHERE Id IN :recordIds AND FieloPLT__Status__c = \'Active\'')) {
                    activeMemberIds.add((Id)member.get('Id'));
                    programsByMembers.put((Id)member.get('Id'),(Id)member.get('FieloPLT__Program__c'));
            }
            programIds.addAll(programsByMembers.values());
            recordIds.retainAll(activeMemberIds);
                

            Map<Id, FieloCC__Communication__c> communicationsMap = new Map<Id, FieloCC__Communication__c>(
                (List<FieloCC__Communication__c>) Database.query(
                    'SELECT ' + namespacePrefix + 'Segment__c,FieloCC__CommunicationCampaign__r.' + namespacePrefix + 'Program__c ' + 
                    'FROM FieloCC__Communication__c ' + 
                    'WHERE Id IN :communicationIds AND  FieloCC__CommunicationCampaign__r.' + namespacePrefix + 'Program__c ' +' IN :programIds'
                )
            );

            Map<Id,Map<Id, Set<Id>>> communicationsBySegmentByProgram = new Map<Id,Map<Id, Set<Id>>> ();

            for (FieloCC__Communication__c communication : communicationsMap.values()) {
                Id segmentId = (Id)communication.get(namespacePrefix + 'Segment__c');
                Id programId = (Id)communication.getSObject('FieloCC__CommunicationCampaign__r').get(namespacePrefix + 'Program__c');

                if(communicationsBySegmentByProgram.containsKey(programId)){
                    if (communicationsBySegmentByProgram.get(programId).containsKey(segmentId)) {
                        communicationsBySegmentByProgram.get(programId).get(segmentId).add(communication.Id);
                    } else {
                        communicationsBySegmentByProgram.get(programId).put(segmentId, new Set<Id>{communication.Id});
                    }
                } else {
                    communicationsBySegmentByProgram.put(programId, new Map<Id, Set<Id>>{segmentId => new Set<Id>{communication.Id}});
                }
            }

            Map<Id, Set<Id>> segmentsByMember = new Map<Id, Set<Id>>();
            for (Id memberId : recordIds) {
                Id programId = programsByMembers.get(memberId);
                Set<Id> segmentIds = communicationsBySegmentByProgram.get(programId)?.keySet();
                segmentsByMember.put(memberId, segmentIds.clone());
            }

            FieloPLT.SegmentService.verifySegments(segmentsByMember);

            List<FieloCC__CommunicationRequest__c> requestsToInsert = new List<FieloCC__CommunicationRequest__c>();
            for (Id memberId : recordIds) {
                for (Id segmentId : segmentsByMember.get(memberId)) {
                    Id programId = programsByMembers.get(memberId);
                    for (Id communicationId : communicationsBySegmentByProgram?.get(programId)?.get(segmentId)) {
                        // TODO: add lookup to execution
                        requestsToInsert.add(
                            new FieloCC__CommunicationRequest__c(
                                FieloCC__Target__c = memberId,
                                FieloCC__Communication__c = communicationId
                            )
                        );
                        communicationWithRequests.add(communicationId);
                    }
                }
                // execution.LastTargetProcessed__c = memberId;
            }

            if (!requestsToInsert.isEmpty()) {
                insert requestsToInsert;
            }
        } catch (Exception e) {
            System.debug(
                e.getMessage()  + ' - ' +
                e.getCause()    + ' - ' +
                e.getStackTraceString()
            );
            if (!Test.isRunningTest()) throw e;
        }
        return communicationWithRequests;
    }
}
