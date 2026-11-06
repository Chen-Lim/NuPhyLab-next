import Foundation

/// Stable stored identifiers, independent of the app's interface language.
/// The old release always translated to Simplified Chinese, so missing values
/// keep that behavior. Unknown values are rejected instead of becoming prompts.
enum LabTranslationLanguage:String,Codable,CaseIterable {
    case simplifiedChinese="zh-CN",traditionalChinese="zh-TW",english="en",japanese="ja",korean="ko"
    case french="fr",german="de",spanish="es",portuguese="pt",italian="it",russian="ru"
    case arabic="ar",hindi="hi",thai="th",vietnamese="vi",indonesian="id"
    var englishName:String {
        switch self {
        case .simplifiedChinese:return "Simplified Chinese"
        case .traditionalChinese:return "Traditional Chinese"
        case .english:return "English"
        case .japanese:return "Japanese"
        case .korean:return "Korean"
        case .french:return "French"
        case .german:return "German"
        case .spanish:return "Spanish"
        case .portuguese:return "Portuguese"
        case .italian:return "Italian"
        case .russian:return "Russian"
        case .arabic:return "Arabic"
        case .hindi:return "Hindi"
        case .thai:return "Thai"
        case .vietnamese:return "Vietnamese"
        case .indonesian:return "Indonesian"
        }
    }
    func title(in language:AppLanguage)->String {
        guard language == .zh else{return englishName}
        switch self {
        case .simplifiedChinese:return "简体中文"
        case .traditionalChinese:return "繁体中文"
        case .english:return "英语"
        case .japanese:return "日语"
        case .korean:return "韩语"
        case .french:return "法语"
        case .german:return "德语"
        case .spanish:return "西班牙语"
        case .portuguese:return "葡萄牙语"
        case .italian:return "意大利语"
        case .russian:return "俄语"
        case .arabic:return "阿拉伯语"
        case .hindi:return "印地语"
        case .thai:return "泰语"
        case .vietnamese:return "越南语"
        case .indonesian:return "印度尼西亚语"
        }
    }
}
