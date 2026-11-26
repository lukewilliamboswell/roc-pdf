app [target] {
	deflate: "https://github.com/lukewilliamboswell/roc-deflate/releases/download/0.4.0-rc4/FoGWbhCP9K1Qk7HA9wcSxHYTpiwTHmCpfNUZx7rAGSSk.tar.zst",
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.8.0/BUNcJDHxCd7xLVSe3WBioyXqR6tm1MqXwzwGgtnmqK43.tar.zst",
	pdf: "../package/all.roc",
}

import fuzz.Fuzz
import FootnoteProperty

target = Fuzz.suite([FootnoteProperty.target])
