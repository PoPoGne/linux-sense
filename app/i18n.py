"""Small translation layer for the Linux Sense UI.

Source strings are English and double as keys: a translation file maps an
English string to the same string in another language. Missing entries fall
back to English, so a partial translation is always safe.

Language files live in app/translations/<code>.json and are plain JSON
objects: {"Battery": "Batteria", ...}.
"""

import json
from pathlib import Path

DEFAULT_LANGUAGE = "en"
TRANSLATIONS_DIR = Path(__file__).resolve().parent / "translations"


def available_languages():
    """Language codes that ship a translation file, English included."""
    codes = {DEFAULT_LANGUAGE}
    if TRANSLATIONS_DIR.is_dir():
        codes.update(p.stem for p in TRANSLATIONS_DIR.glob("*.json"))
    return sorted(codes)


def normalize(code):
    """Turn a locale such as it_IT.UTF-8 or it-IT into it."""
    if not code:
        return DEFAULT_LANGUAGE
    code = code.split(".", 1)[0].split("@", 1)[0].replace("-", "_")
    language = code.split("_", 1)[0].lower()
    return language if language else DEFAULT_LANGUAGE


class Translator:
    def __init__(self, language=None):
        self.language = self._pick(language)
        self._strings = self._load(self.language)

    @staticmethod
    def _pick(language):
        candidates = [normalize(language)] if language else []
        candidates.append(DEFAULT_LANGUAGE)
        for code in candidates:
            if (TRANSLATIONS_DIR / f"{code}.json").is_file():
                return code
        return DEFAULT_LANGUAGE

    @staticmethod
    def _load(language):
        path = TRANSLATIONS_DIR / f"{language}.json"
        if not path.is_file():
            return {}
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return {}
        return {k: v for k, v in data.items() if isinstance(v, str) and v}

    def t(self, text):
        """Translate one string, falling back to the English source."""
        return self._strings.get(text, text)

    def fmt(self, text, values=None):
        """Translate then substitute {name} placeholders."""
        result = self.t(text)
        for name, value in (values or {}).items():
            result = result.replace("{" + name + "}", str(value))
        return result
