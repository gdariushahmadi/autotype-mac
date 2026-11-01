import Foundation

/// Persian words that have no English equivalent.
///
/// Their Latin spelling is a word in the English dictionary — an
/// abbreviation, a state code, a musical note — so the two dictionaries
/// would call them ambiguous: «از» is spelled `hc`, «یا» is spelled `dh`,
/// «در» is spelled `nv`. In Persian typing they are everyday function words
/// with one unmistakable reading, and the English reading is meaningless, so
/// they always count as Persian.
///
/// Words whose spelling is a *real* English word (`fun` / «بعد», `leg` /
/// «مثل») are deliberately absent: those really are ambiguous and the
/// sentence around them decides.
public enum PersianOnlyWords {

    /// The words themselves, in Persian.
    public static let words: Set<String> = [
        "از",   // hc
        "به",   // fi
        "یا",   // dh
        "در",   // nv
        "هر",   // iv
        "پس",   // ms
        "هم",   // il
        "تا",   // jh
        "با",   // fh
        "می",   // ld
        "من",   // lk
        "ما",   // lh
        "تو",   // j,
        "رو",   // v,
        "دو",   // n,
        "سه",   // si
        "نه",   // ki
        "دل",   // ng
        "که",   // ;i
        "این",  // hdk
        "آن",   // hk
        "اب",   // hf

        // High-frequency Persian words whose Latin keys match non-word English abbreviations/codes
        "یک",   // d;
        "و",    // ,
        "او",   // h,
        "چه",   // ]i
        "چو",   // ],
        "چون",  // ],k
        "کی",   // ;d
        "کو",   // ;,
        "اگر",  // h'v
        "مگر",  // l'v
        "گر",   // 'v
        "بر",   // fv
        "بی",   // fd
        "هی",   // id
        "ای",   // hd
        "اه",   // hi
        "ده",   // ni
        "دی",   // nd
        "دم",   // nl
        "پر",   // mv
        "پا",   // mh
        "پی",   // md
        "پل",   // mg
        "مه",   // li
        "شب",   // af
        "سر",   // sv
        "حد",   // pn
        "حق",   // pr
        "حل",   // pg
        "حس",   // ps
        "خم",   // ol
        "زر",   // cv
        "رس",   // vs
        "ره",   // vi
        "بس",   // fs
        "بل",   // fg
        "سگ",   // s'
        "هیچ",  // id] / dn]
        "پنج",  // mk[
        "یکی",  // d;d
        "یکبار",// d;fhv
        "یکدیگر", // d;nd'v

        // Standalone Persian alphabet letters (whose Latin keystrokes are not English words)
        "ا", "ب", "پ", "ت", "ث", "ج", "چ", "ح", "خ", "د", "ذ", "ر", "ز", "ژ",
        "س", "ص", "ض", "ط", "ظ", "ع", "غ", "ف", "ق", "ک", "گ", "ل", "م", "ن", "ی", "آ",
    ]

    /// `true` when the Persian word has no English equivalent.
    ///
    /// The comparison ignores the zero width non-joiner and the Arabic
    /// letter variants, so «می‌رود» and «میرود» compare equal.
    public static func contains(_ persian: String) -> Bool {
        words.contains(PersianText.lookupKey(persian))
    }
}
