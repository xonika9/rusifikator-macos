enum CharacterCountFormatter {
    static func string(for count: Int) -> String {
        "\(count) \(word(for: count))"
    }

    private static func word(for count: Int) -> String {
        let lastTwo = count % 100
        let last = count % 10
        if (11...14).contains(lastTwo) {
            return "знаков"
        }
        switch last {
        case 1:
            return "знак"
        case 2...4:
            return "знака"
        default:
            return "знаков"
        }
    }
}
