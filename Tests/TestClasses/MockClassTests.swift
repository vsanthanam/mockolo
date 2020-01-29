
import Foundation

class MockClassTests: MockoloTestCase {
    
    func testMockClass() {
//        verify(srcContent: klass,
//               dstContent: klassMock,
//               useDefaultParser: true)
    }
    
    func testMockClassWithParent() {
//        verify(srcContent: klass,
//               mockContent: klassParentMock,
//               dstContent: klassLongerMock,
//               useDefaultParser: true)
    }

    func testMockClassInits() {
//        verify(srcContent: qlass,
//               mockContent: qlassParentMock,
//               dstContent: qlassLongerMock,
//               useDefaultParser: true)
    }
}



class x {
    init(arg: Int) {}
    
    convenience init(omg: String) {self.init(arg: 3)}
}


class y: x {
    override init(arg: Int) {super.init(arg: arg)}
    convenience init(omg: String) { self.init(arg: 3)}
}




