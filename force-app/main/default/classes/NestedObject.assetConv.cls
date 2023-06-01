global class NestedObject {
    @AuraEnabled
    public List<NestedObject> children;
    @AuraEnabled
    public String parentId;
    private String rootId;
    @AuraEnabled
    public Nestable obj;
    private Map<String, Object> data = new Map<String, Object>();
    // private Map<String, Boolean> bFlags = new Map<String, Boolean>();
    // private Map<String, String> sFlags = new Map<String, String>();

    /**
     * @param obj the base object to create the NestedObject from
     * @description Basic constructor
     */
    // public NestedObject (SObject obj) {
    //     this.obj = new NestableSObject(obj);
    //     if(obj != null) {
    //         this.rootId = obj.Id;
    //     }
    // }

    public NestedObject (Nestable obj) {
        this.obj = obj;
        if(obj != null) {
            this.rootId = obj.Id;
        }
    }

    public NestedObject (AssignResult ar) {
        this.obj = ar.obj;
        this.rootId = ar.obj.Id;
        this.data = ar.data;
        // this.bFlags = ar.bFlags;
        // this.sFlags = ar.sFlags;
    }

    /** 
     * @param objs List of SObjects to create the nested object from
     * @param key Field (String) to be used as identifier of an SObject instance in objs for purposes of establishing parent-child relationship.
     * @param parentKey Field (String) to be used as identifer of the parent of an SObject instance in objs. The SObject instance in objs with it's 'key' value equal to the value of 'parentKey' is the parent of any particular instance.
     */
    public NestedObject (List<Nestable> objs, String key, String parentKey) {
        this.initiate(objs, key, parentKey);
    }

    public NestedObject (List<SObject> sobjs, String key, String parentKey) {
        List<NestableSObject> objs = new List<NestableSObject>();
        for (SObject sobj : sobjs) {
            objs.add(new NestableSObject(sobj));
        }
        this.initiate(objs, key, parentKey);
    }

    private void initiate(List<Nestable> objs, String key, String parentKey) {
        List<String> addedKeys = new List<String>();
        List<Nestable> working = objs;
        List<Nestable> staged = new List<Nestable>();
        Boolean rootFound = false;
        Boolean multiRoot = false;
        while (working.size() > 0) {
            Integer count = 0;
            for (Nestable obj : working) {
                count++;
                String parentId = (String) obj.get(parentKey);
                if(parentId == null || parentId == 'null' || parentId == '') {
                    if(rootFound && !multiRoot) {
                        //multiple roots
                        NestedObject selfClone = this.clone();
                        if(PWUtils.isId(this.obj.Id)) {
                            this.obj = new NestableSObject(((Id) this.obj.Id).getSObjectType().newSObject());
                        } else {
                            throw new NestedObjectException('Cannot create instance of object from id: [' + this.obj.Id + ']');
                        }
                        this.children = new List<NestedObject>{selfClone};
                        this.rootId = this.obj.Id;
                        this.resetIds(true);
                        this.addChild(obj);
                        multiRoot = true;
                    } else if (rootFound && multiRoot) {
                        this.addChild(obj);
                    } else {
                        this.obj = obj;
                        this.rootId = obj.Id;
                    }
                    rootFound = true;
                    addedKeys.add((String) obj.get(key));
                } else if (addedKeys.contains(parentId)) {
                    NestedObject parent = this.findByKey(key, parentId);
                    if(parent != null) {
                        parent.addChild(obj);
                        addedKeys.add((String) obj.get(key));
                    }
                } else {
                    staged.add(obj); // come back once the parent has been added
                }
            }
            if(working == staged) {
                throw new NestedObjectException('Repeating loop detected.');
            }
            working = staged;
            staged = new List<Nestable>();
        }
    }

    private NestedObject (Nestable obj, NestedObject parent) {
        this.obj = obj;
        this.parentId = parent.obj.Id;
        this.rootId = parent.rootId;
    }

    // public NestedObject addChild(SObject child) {
    //     return this.addChild(new NestableSObject(child));
    // }

    public NestedObject addChild(Nestable child) {
        if(this.children == null) {
            this.children = new List<NestedObject>();
        }
        NestedObject childNo = new NestedObject(child, this);
        this.children.add(childNo);
        return childNo;
    }

    public NestedObject addChild(NestedObject child) {
        if(this.children == null) {
            this.children = new List<NestedObject>();
        }
        if(this.obj != null) {
            child.parentId = this.obj.Id;
        }
        child.rootId = this.rootId;
        this.children.add(child);
        return child;
    }

    public NestedObject add(SObject child, String parentId) {
        return this.add(new NestableSObject(child), parentId);
    }

    public NestedObject add(Nestable descendant, String parentId) {
        NestedObject parent = this.findById(parentId);
        if(parent == null) {
            parent = this;
        }
        return parent.addChild(descendant);
    }

    public NestedObject findById (String id) {
        System.debug(this.obj);
        if(this.obj.Id == id) {
            return this;
        } else if (this.children != null) {
            for (NestedObject child : this.children) {
                NestedObject found = child.findById(id);
                if(found != null) {
                    return found;
                }
            }
        }
        // if(Test.isRunningTest()){
            // System.debug('NO MATCH');
            // System.debug('OBJ:'); System.debug(this.obj);
            // System.debug('OBJ ID: ' + this.obj.Id);
            // System.debug('Query id: ' + id);
        // }
        return null;
    }
    
    public NestedObject findByKey (String keyField, String keyValue) {
        Boolean thisMatch = false;
        try {
            thisMatch = this.obj.get(keyfield) == keyValue;
        } catch (SObjectException e) {
            if(e.getMessage().startsWith('Invalid field')) {
                // do nothing - this can happen when searching through a tree of mixed types
            } else {
                throw e;
            }
        }
        if(thisMatch) {
            return this;
        } else if (this.children != null) {
            for (NestedObject child : this.children) {
                NestedObject found = child.findByKey(keyField, keyValue);
                if(found != null) {
                    return found;
                }
            }
        }
        return null;
    }
    
    public List<NestedObject> all() {
        List<NestedObject> all = new List<NestedObject>();
        all.add(this);
        if(this.children != null) {
            for (NestedObject child : this.children) {
                all.addAll(child.all());
            }
        }
        return all;
    }

    public List<NestedObject> bottomUp() {
        List<NestedObject> all = new List<NestedObject>();
        if(this.children != null) {
            for (NestedObject child : this.children) {
                all.addAll(child.bottomUp());
            }
        }
        all.add(this);
        return all;
    }

    // public List<NestedObject> some(FilterFunction func) {
    //     List<NestedObject> filteredList = new List<NestedObject>();
    //     for (NestedObject node : this.all()) {
    //         if(func.test(node.obj, node.data)) {
    //             filteredList.add(node);
    //         }
    //     }
    //     return filteredList;
    // }

    public NestedObject find(FilterFunction func) {
        for (NestedObject node : this.all()) {
            if(func.test(node.obj, data)) {
                return node;
            }
        }
        return null;
    }

    private void resetIds(Boolean rootChanged) {
        if(this.children != null && this.obj != null) {
            for(NestedObject child : this.children) {
                child.parentId = this.obj.Id;
            }
            if(rootChanged) {
                for (NestedObject obj : this.all()) {
                    obj.rootId = this.rootId;
                }
            }
        }
    }

    // public void replaceObject(SObject obj) {
    //     this.replaceObject(new NestableSObject(obj));
    // }

    public NestedObject getParent() {
        return this.findById(this.parentId);
    }

    public void replaceObject(Nestable obj) {
        Boolean rootChanged = false;
        if((this.rootId == null && obj.Id != null) || this.rootId == this.obj.Id) {
            // this is the root item
            this.rootId = obj.Id;
            rootChanged = true;
        }
        this.obj = obj;
        this.resetIds(rootChanged);
    }

    public List<NestedObject> replaceObject(List<Nestable> objs) {
        if(objs.size() == 1) {
            this.replaceObject(objs[0]);
            return;
        }
        if(this.children != null && this.children.size() > 0) {
            throw new NestedObjectException('Cannot replace object which has children.');
        }
        this.remove(this.id);
        NestedObject parent = this.getParent();
        Integer startIdx = parent.children.size();
        for (Nestable obj : objs) {
            parent.addChild(obj);
        }
        return PWUtils.slice(parent.children, startIdx);
    }

    public void remove(String id) {
        NestedObject toRemove = this.findById(id);
        NestedObject parent = this.findById(toRemove.parentId);
        List<NestedObject> newChildren = new List<NestedObject>();
        if(toRemove.children != null) {
            newChildren.addAll(toRemove.children);
        }
        for (NestedObject child : parent.children) {
            if(child.obj.getId() != id) {
                newChildren.add(child);
            }
        }
        parent.children = newChildren;
        parent.resetIds(false);
    }

    // public List<NestedObject> filter(FilterFunction func) {
    //     // 1. get filtered list of children, calling this method recursively on each
    //     List<NestedObject> children;
    //     if(this.children != null) {
    //         children = new List<NestedObject>();
    //         for (NestedObject no : this.children) {
    //             List<NestedObject> filteredChildren = no.filter(func);
    //             if(filteredChildren != null) {
    //                 children.addAll(filteredChildren);
    //             }
    //         }
    //         if(children.size() == 0) {
    //             children = null;
    //         }
    //     }
    //     // 2. If this object is valid, return only this object (after resetting any ids)
    //     if(func.test(this.obj, this.data)) {
    //         NestedObject clone = this.clone();
    //         clone.children = children;
    //         clone.resetIds(false);
    //         clone.parentId = null; // this should get reset when it's ultimate parent calls resetIds(), but if it ends up not having a parent, it will stay null (which is good)
    //         return new List<NestedObject>{clone};
    //     } else {
    //         // 3. Else return only the children, omitting this node
    //         return children;
    //     }
    // }

    // public NestedObject rollUp(RollUpFunction func) {
    //     List<NestedObject> rolledUpChildObjs = new List<NestedObject>();
    //     if(this.children != null) {
    //         for (NestedObject child : this.children) {
    //             child.rollUp(func);
    //             rolledUpChildObjs.add(child);
    //         }
    //     }
    //     func.forEach(this, rolledUpChildObjs);
    //     return this;
    // }

    

    /**
     * @description iterate over source nodes and search target for matching node, based on source and target ID fields
     *  if there's a match, call assignFunc to determine resulting sObj and flags to replace match in target
     *  if there's no match, look for a match on the source parent and add source node as new child to that parent.
     *  if a scopeFunc is provided, limit the above to only those nodes that pass the scopeFunc filtering (this is primarily for performance & any gov limits in the assignment function)
     * @param  target              target description
     * @param  source              source description
     * @param  targetIdField       targetIdField description
     * @param  sourceIdField       sourceIdField description
     * @param  sourceParentIdField sourceParentIdField description
     * @param  scopeFunc           scopeFunc description
     * @param  assignFunc          assignFunc description
     * @return NestedObject        return description
     */
    public static NestedObject assign(NestedObject target, NestedObject source, String targetIdField, String sourceIdField, String sourceParentIdField, FilterFunction scopeFunc, AssignFunction assignFunc) {
        // iterate over source nodes and search target for matching node, based on source and target ID fields
        //      if there's a match, call assignFunc to determine resulting sObj and flags to replace match in target
        //      if there's no match, look for a match on the source parent and add source node as new child to that parent.
        //      if a scopeFunc is provided, limit the above to only those nodes that pass the scopeFunc filtering (this is primarily for performance & any gov limits in the assignment function)
        //      
        NestedObject result = target.clone();
        List<NestedObject> filteredSource = new List<NestedObject>{source};
        if(scopeFunc != null) {
            throw new NestedObjectException('Scope functions are currently disabled');
            // filteredSource = source.filter(scopeFunc);
        }
        for (NestedObject rootNO : filteredSource) {
            for (NestedObject no : rootNO.all()) {
                if(scopeFunc != null) {
                    // If source is filtered, retrieve the base node from the source based on the filtered node (the filtering will have changed the parental relationships, etc.)
                    no = source.findById(no.obj.Id);
                }
                NestedObject match;
                try {
                    String sourceIdVal = (String) no.obj.get(sourceIdField);
                    if(sourceIdVal != null) {
                        match = result.findByKey(targetIdField, sourceIdVal);
                    }
                } catch (SObjectException e) {
                    if(e.getMessage().startsWith('Invalid field')) {
                        continue;
                    } else {
                        throw e;
                    }
                }
                if(match != null) {
                    AssignResult assignResult = assignFunc.assign(match.obj, no.obj, match.data);
                    match.obj = assignResult.obj;
                    match.data = assignResult.data;
                    // match.bFlags = assignResult.bFlags;
                    // match.sFlags = assignResult.sFlags;
                } else {
                    NestedObject parentMatch = result.findByKey(targetIdField, (String) no.obj.get(sourceParentIdField));
                    if(parentMatch != null) {
                        AssignResult assignResult = assignFunc.assign(null, no.obj, new Map<String, Object>());
                        parentMatch.addChild(new NestedObject(assignResult));
                    }
                }
            }
        }
        return result;
    }

    public static void setData(List<NestedObject> nodes, String key, Object val) {
        for (NestedObject node : nodes) {
            node.setData(key, val);
        }
    }
    public void setData (String key, Object val) {
        this.data.put(key, val);
    }
    public Object getData (String key) {
        // System.debug(JSON.serialize(this.data));
        if(this.data.containsKey(key)) {
            return this.data.get(key);
        }
        return null;
    }

    /*
    public void setFlag (String key, Boolean val) {
        this.bFlags.put(key, val);
    }

    public void setFlag (String key, String val) {
        this.sFlags.put(key, val);
    }

    public Boolean getBFlag (String key) {
        return this.bFlags.get(key);
    }

    public String getSFlag (String key) {
        return this.sFlags.get(key);
    }
    */

    public interface FilterFunction {
        // Boolean test(SObject obj, Map<String, Boolean> bFlags, Map<String, String> sFlags);
        Boolean test(Nestable obj, Map<String, Object> data);
    }

    public interface RollUpFunction {
        void forEach(NestedObject no, List<NestedObject> children);
    }

    public class AssignResult {
        // public Map<String, Boolean> bFlags;
        // public Map<String, String> sFlags;
        public Map<String, Object> data;
        public Nestable obj;

        public AssignResult(){
            // this.bFlags = new Map<String, Boolean>();
            // this.sFlags = new Map<String, String>();
            this.data = new Map<String, Object>();
        }

        public AssignResult(SObject obj, Map<String, Object> data) {
            this.obj = new NestableSObject(obj);
            this.data = data;
        }

        public AssignResult(Nestable obj, Map<String, Object> data) {
            this.obj = obj;
            // this.bFlags = bFlags;
            // this.sFlags = sFlags;
            this.data = data;
        }
    }
    
    public interface AssignFunction {
        AssignResult assign(Nestable targetObj, Nestable sourceObj, Map<String, Object> data);
    }

    public SanitisedNestedObject sanitise() {
        return new SanitisedNestedObject(this);
    }

    global class SanitisedNestedObject {
        @AuraEnabled
        public List<SanitisedNestedObject> children;
        @AuraEnabled
        public String parentId;
        @AuraEnabled
        public Nestable obj;

        public SanitisedNestedObject (NestedObject no) {
            this.obj = no.obj;
            this.parentId = no.parentId;
            if(no.children != null) {
                this.children = new List<SanitisedNestedObject>();
                for (NestedObject child : no.children) {
                    this.children.add(new SanitisedNestedObject(child));
                }
            }
        }
    }

    public abstract class Nestable {
        public String Id {
            get {
                return this.getId();
            }
            set {
                this.setId(value);
            }
        }
        public abstract Object get(String key);
        protected abstract String getId();
        protected abstract void setId(String value);
    }

    public class NestableSObject extends Nestable {
        public SObject obj;

        public NestableSObject(SObject obj) {
            this.obj = obj;
            this.Id = obj.Id;
        }
        public override Object get(String key) {
            return PWUtils.getField(this.obj,key);
        }
        protected override String getId(){
            return this.obj.Id;
        }
        protected override void setId(String value) {
            this.obj.Id = value;
        }
    }

    public class NestedObjectException extends Exception{}

}