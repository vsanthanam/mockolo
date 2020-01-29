//import MockoloFramework
//
//
//
//
//
////
////public class TallMock: Tall {
////    override public init(count: Int) {
////        super.init(count: count)
////    }
////    override public init() {
////        super.init()
////    }
////}
////
////public class Tall: Grande {
////    public init(count: Int) {}
////}
////
////public class Grande: Venti {
////}
////
////public class Venti {
////    public init() {}
////}
//
////let qlass =
////"""
///// \(String.mockAnnotation)
//public class Low: Mid {
//    var name: String = ""
//    public required init(arg: String) {
//        super.init(orderId: 1)
//        self.name = arg
//    }
//
////    public override init(orderId: Int) {
////        super.init(orderId: orderId)
////    }
//
//    public init(m: Int) {
//        super.init(orderId: m)
//    }
//}
//
//public class Mid: High {
//    var what: Double = 0.0
//}
////"""
////
////let qlassParent =
////"""
//
//public class High {
//    var order: Int
//    
//    public init(orderId: Int) {
//        self.order = orderId
//    }
//    
//    public init(loc: String) {
//        self.order = 0
//    }
//    
//    func bar() {}
//}
////"""
////
////let qlassParentMock =
////"""
//public class HighMock: High {
//    private var _doneInit = false
//
//    override init(orderId: Int) {
//        super.init(orderId: orderId)
//        _doneInit = true
//    }
//}
//
////"""
////
////let qlassMock =
////"""
//    public class LowMock: Low {
//
//        private var _doneInit = false
//            
//        public var nameSetCallCount = 0
//        var underlyingName: String = ""
//        public override var name: String {
//            get { return underlyingName }
//            set {
//                underlyingName = newValue
//                if _doneInit { nameSetCallCount += 1 }
//            }
//        }
//        required public init(arg: String) {
//            super.init(arg: arg)
//            _doneInit = true
//        }
//        
////        override public init(orderId: Int) {
////            super.init(orderId: orderId)
////            _doneInit = true
////        }
//        
//        override public init(m: Int) {
//            super.init(m: m)
//            _doneInit = true
//        }
//        
//        public var whatSetCallCount = 0
//        var underlyingWhat: Double = 0.0
//        public override var what: Double {
//            get { return underlyingWhat }
//            set {
//                underlyingWhat = newValue
//                if _doneInit { whatSetCallCount += 1 }
//            }
//        }
//        public var barCallCount = 0
//        public var barHandler: (() -> ())?
//        public override func bar()  {
//            barCallCount += 1
//
//            if let barHandler = barHandler {
//                barHandler()
//            }
//            
//        }
//    }
//
////"""
////
////let qlassLongerMock =
////"""
//    public class LowMock2: Low {
//
//        private var _doneInit = false
//            
//        
//            
//        public var nameSetCallCount = 0
//        var underlyingName: String = ""
//        public override var name: String {
//            get { return underlyingName }
//            set {
//                underlyingName = newValue
//                if _doneInit { nameSetCallCount += 1 }
//            }
//        }
//        required public init(arg: String) {
//            super.init(arg: arg)
//            _doneInit = true
//        }
//        override public init(m: Int) {
//            super.init(m: m)
//            _doneInit = true
//        }
//
//        var orderSetCallCount = 0
//
//        var underlyingOrder: Int = 0
//        
//        public var whatSetCallCount = 0
//        var underlyingWhat: Double = 0.0
//        public override var what: Double {
//            get { return underlyingWhat }
//            set {
//                underlyingWhat = newValue
//                if _doneInit { whatSetCallCount += 1 }
//            }
//        }
//
//        override var order: Int {
//            get { return underlyingOrder }
//            set {
//                underlyingOrder = newValue
//                if _doneInit { orderSetCallCount += 1 }
//            }
//        }
//
//        public var barCallCount = 0
//        public var barHandler: (() -> ())?
//        public override func bar()  {
//            barCallCount += 1
//
//            if let barHandler = barHandler {
//                barHandler()
//            }
//        }
//    }
//
////"""
