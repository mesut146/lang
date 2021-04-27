// Generated from /home/mesut/Desktop/lang/Lexer.g by ANTLR 4.8
import org.antlr.v4.runtime.Lexer;
import org.antlr.v4.runtime.CharStream;
import org.antlr.v4.runtime.Token;
import org.antlr.v4.runtime.TokenStream;
import org.antlr.v4.runtime.*;
import org.antlr.v4.runtime.atn.*;
import org.antlr.v4.runtime.dfa.DFA;
import org.antlr.v4.runtime.misc.*;

@SuppressWarnings({"all", "warnings", "unchecked", "unused", "cast"})
public class Lexer extends Lexer {
	static { RuntimeMetaData.checkVersion("4.8", RuntimeMetaData.VERSION); }

	protected static final DFA[] _decisionToDFA;
	protected static final PredictionContextCache _sharedContextCache =
		new PredictionContextCache();
	public static final int
		CLASS=1, ENUM=2, INTERFACE=3, IMPORT=4, AS=5, BREAK=6, CASE=7, CONTINUE=8, 
		DO=9, ELSE=10, FOR=11, IF=12, LET=13, RETURN=14, WHILE=15, SWITCH=16, 
		VAR=17, LPAREN=18, RPAREN=19, LBRACE=20, RBRACE=21, LBRACK=22, RBRACK=23, 
		SEMI=24, COMMA=25, DOT=26, ELLIPSIS=27, AT=28, COLONCOLON=29, ASSIGN=30, 
		GT=31, LT=32, BANG=33, TILDE=34, QUESTION=35, COLON=36, ARROW=37, EQUAL=38, 
		LE=39, GE=40, NOTEQUAL=41, AND=42, OR=43, INC=44, DEC=45, ADD=46, SUB=47, 
		MUL=48, DIV=49, BITAND=50, BITOR=51, CARET=52, MOD=53, ADD_ASSIGN=54, 
		SUB_ASSIGN=55, MUL_ASSIGN=56, DIV_ASSIGN=57, AND_ASSIGN=58, OR_ASSIGN=59, 
		XOR_ASSIGN=60, MOD_ASSIGN=61, LSHIFT_ASSIGN=62, RSHIFT_ASSIGN=63, URSHIFT_ASSIGN=64, 
		CHAR=65, BYTE=66, SHORT=67, INT=68, LONG=69, FLOAT=70, DOUBLE=71, BOOLEAN=72, 
		BOOLEAN_LIT=73, NULL_LIT=74, INTEGER_LIT=75, FLOAT_LIT=76, CHAR_LIT=77, 
		STRING_LIT=78, IDENT=79, WS=80, BLOCK_COMMENT=81, LINE_COMMENT=82;
	public static String[] channelNames = {
		"DEFAULT_TOKEN_CHANNEL", "HIDDEN"
	};

	public static String[] modeNames = {
		"DEFAULT_MODE"
	};

	private static String[] makeRuleNames() {
		return new String[] {
			"CLASS", "ENUM", "INTERFACE", "IMPORT", "AS", "BREAK", "CASE", "CONTINUE", 
			"DO", "ELSE", "FOR", "IF", "LET", "RETURN", "WHILE", "SWITCH", "VAR", 
			"LPAREN", "RPAREN", "LBRACE", "RBRACE", "LBRACK", "RBRACK", "SEMI", "COMMA", 
			"DOT", "ELLIPSIS", "AT", "COLONCOLON", "ASSIGN", "GT", "LT", "BANG", 
			"TILDE", "QUESTION", "COLON", "ARROW", "EQUAL", "LE", "GE", "NOTEQUAL", 
			"AND", "OR", "INC", "DEC", "ADD", "SUB", "MUL", "DIV", "BITAND", "BITOR", 
			"CARET", "MOD", "ADD_ASSIGN", "SUB_ASSIGN", "MUL_ASSIGN", "DIV_ASSIGN", 
			"AND_ASSIGN", "OR_ASSIGN", "XOR_ASSIGN", "MOD_ASSIGN", "LSHIFT_ASSIGN", 
			"RSHIFT_ASSIGN", "URSHIFT_ASSIGN", "CHAR", "BYTE", "SHORT", "INT", "LONG", 
			"FLOAT", "DOUBLE", "BOOLEAN", "BOOLEAN_LIT", "NULL_LIT", "INTEGER_LIT", 
			"FLOAT_LIT", "CHAR_LIT", "STRING_LIT", "IDENT", "WS", "BLOCK_COMMENT", 
			"LINE_COMMENT"
		};
	}
	public static final String[] ruleNames = makeRuleNames();

	private static String[] makeLiteralNames() {
		return new String[] {
			null, "'class'", "'enum'", "'interface'", "'import'", "'as'", "'break'", 
			"'case'", "'continue'", "'do'", "'else'", "'for'", "'if'", "'let'", "'return'", 
			"'while'", "'switch'", "'var'", "'('", "')'", "'{'", "'}'", "'['", "']'", 
			"';'", "','", "'.'", "'...'", "'@'", "'::'", "'='", "'>'", "'<'", "'!'", 
			"'~'", "'?'", "':'", "'->'", "'=='", "'<='", "'>='", "'!='", "'&&'", 
			"'||'", "'++'", "'--'", "'+'", "'-'", "'*'", "'/'", "'&'", "'|'", "'^'", 
			"'%'", "'+='", "'-='", "'*='", "'/='", "'&='", "'|='", "'^='", "'%='", 
			"'<<='", "'>>='", "'>>>='", "'char'", "'byte'", "'short'", "'int'", "'long'", 
			"'float'", "'double'", "'boolean'", null, "'null'"
		};
	}
	private static final String[] _LITERAL_NAMES = makeLiteralNames();
	private static String[] makeSymbolicNames() {
		return new String[] {
			null, "CLASS", "ENUM", "INTERFACE", "IMPORT", "AS", "BREAK", "CASE", 
			"CONTINUE", "DO", "ELSE", "FOR", "IF", "LET", "RETURN", "WHILE", "SWITCH", 
			"VAR", "LPAREN", "RPAREN", "LBRACE", "RBRACE", "LBRACK", "RBRACK", "SEMI", 
			"COMMA", "DOT", "ELLIPSIS", "AT", "COLONCOLON", "ASSIGN", "GT", "LT", 
			"BANG", "TILDE", "QUESTION", "COLON", "ARROW", "EQUAL", "LE", "GE", "NOTEQUAL", 
			"AND", "OR", "INC", "DEC", "ADD", "SUB", "MUL", "DIV", "BITAND", "BITOR", 
			"CARET", "MOD", "ADD_ASSIGN", "SUB_ASSIGN", "MUL_ASSIGN", "DIV_ASSIGN", 
			"AND_ASSIGN", "OR_ASSIGN", "XOR_ASSIGN", "MOD_ASSIGN", "LSHIFT_ASSIGN", 
			"RSHIFT_ASSIGN", "URSHIFT_ASSIGN", "CHAR", "BYTE", "SHORT", "INT", "LONG", 
			"FLOAT", "DOUBLE", "BOOLEAN", "BOOLEAN_LIT", "NULL_LIT", "INTEGER_LIT", 
			"FLOAT_LIT", "CHAR_LIT", "STRING_LIT", "IDENT", "WS", "BLOCK_COMMENT", 
			"LINE_COMMENT"
		};
	}
	private static final String[] _SYMBOLIC_NAMES = makeSymbolicNames();
	public static final Vocabulary VOCABULARY = new VocabularyImpl(_LITERAL_NAMES, _SYMBOLIC_NAMES);

	/**
	 * @deprecated Use {@link #VOCABULARY} instead.
	 */
	@Deprecated
	public static final String[] tokenNames;
	static {
		tokenNames = new String[_SYMBOLIC_NAMES.length];
		for (int i = 0; i < tokenNames.length; i++) {
			tokenNames[i] = VOCABULARY.getLiteralName(i);
			if (tokenNames[i] == null) {
				tokenNames[i] = VOCABULARY.getSymbolicName(i);
			}

			if (tokenNames[i] == null) {
				tokenNames[i] = "<INVALID>";
			}
		}
	}

	@Override
	@Deprecated
	public String[] getTokenNames() {
		return tokenNames;
	}

	@Override

	public Vocabulary getVocabulary() {
		return VOCABULARY;
	}


	public Lexer(CharStream input) {
		super(input);
		_interp = new LexerATNSimulator(this,_ATN,_decisionToDFA,_sharedContextCache);
	}

	@Override
	public String getGrammarFileName() { return "Lexer.g"; }

	@Override
	public String[] getRuleNames() { return ruleNames; }

	@Override
	public String getSerializedATN() { return _serializedATN; }

	@Override
	public String[] getChannelNames() { return channelNames; }

	@Override
	public String[] getModeNames() { return modeNames; }

	@Override
	public ATN getATN() { return _ATN; }

	public static final String _serializedATN =
		"\3\u608b\ua72a\u8133\ub9ed\u417c\u3be7\u7786\u5964\2T\u0205\b\1\4\2\t"+
		"\2\4\3\t\3\4\4\t\4\4\5\t\5\4\6\t\6\4\7\t\7\4\b\t\b\4\t\t\t\4\n\t\n\4\13"+
		"\t\13\4\f\t\f\4\r\t\r\4\16\t\16\4\17\t\17\4\20\t\20\4\21\t\21\4\22\t\22"+
		"\4\23\t\23\4\24\t\24\4\25\t\25\4\26\t\26\4\27\t\27\4\30\t\30\4\31\t\31"+
		"\4\32\t\32\4\33\t\33\4\34\t\34\4\35\t\35\4\36\t\36\4\37\t\37\4 \t \4!"+
		"\t!\4\"\t\"\4#\t#\4$\t$\4%\t%\4&\t&\4\'\t\'\4(\t(\4)\t)\4*\t*\4+\t+\4"+
		",\t,\4-\t-\4.\t.\4/\t/\4\60\t\60\4\61\t\61\4\62\t\62\4\63\t\63\4\64\t"+
		"\64\4\65\t\65\4\66\t\66\4\67\t\67\48\t8\49\t9\4:\t:\4;\t;\4<\t<\4=\t="+
		"\4>\t>\4?\t?\4@\t@\4A\tA\4B\tB\4C\tC\4D\tD\4E\tE\4F\tF\4G\tG\4H\tH\4I"+
		"\tI\4J\tJ\4K\tK\4L\tL\4M\tM\4N\tN\4O\tO\4P\tP\4Q\tQ\4R\tR\4S\tS\3\2\3"+
		"\2\3\2\3\2\3\2\3\2\3\3\3\3\3\3\3\3\3\3\3\4\3\4\3\4\3\4\3\4\3\4\3\4\3\4"+
		"\3\4\3\4\3\5\3\5\3\5\3\5\3\5\3\5\3\5\3\6\3\6\3\6\3\7\3\7\3\7\3\7\3\7\3"+
		"\7\3\b\3\b\3\b\3\b\3\b\3\t\3\t\3\t\3\t\3\t\3\t\3\t\3\t\3\t\3\n\3\n\3\n"+
		"\3\13\3\13\3\13\3\13\3\13\3\f\3\f\3\f\3\f\3\r\3\r\3\r\3\16\3\16\3\16\3"+
		"\16\3\17\3\17\3\17\3\17\3\17\3\17\3\17\3\20\3\20\3\20\3\20\3\20\3\20\3"+
		"\21\3\21\3\21\3\21\3\21\3\21\3\21\3\22\3\22\3\22\3\22\3\23\3\23\3\24\3"+
		"\24\3\25\3\25\3\26\3\26\3\27\3\27\3\30\3\30\3\31\3\31\3\32\3\32\3\33\3"+
		"\33\3\34\3\34\3\34\3\34\3\35\3\35\3\36\3\36\3\36\3\37\3\37\3 \3 \3!\3"+
		"!\3\"\3\"\3#\3#\3$\3$\3%\3%\3&\3&\3&\3\'\3\'\3\'\3(\3(\3(\3)\3)\3)\3*"+
		"\3*\3*\3+\3+\3+\3,\3,\3,\3-\3-\3-\3.\3.\3.\3/\3/\3\60\3\60\3\61\3\61\3"+
		"\62\3\62\3\63\3\63\3\64\3\64\3\65\3\65\3\66\3\66\3\67\3\67\3\67\38\38"+
		"\38\39\39\39\3:\3:\3:\3;\3;\3;\3<\3<\3<\3=\3=\3=\3>\3>\3>\3?\3?\3?\3?"+
		"\3@\3@\3@\3@\3A\3A\3A\3A\3A\3B\3B\3B\3B\3B\3C\3C\3C\3C\3C\3D\3D\3D\3D"+
		"\3D\3D\3E\3E\3E\3E\3F\3F\3F\3F\3F\3G\3G\3G\3G\3G\3G\3H\3H\3H\3H\3H\3H"+
		"\3H\3I\3I\3I\3I\3I\3I\3I\3I\3J\3J\3J\3J\3J\3J\3J\3J\3J\5J\u01b6\nJ\3K"+
		"\3K\3K\3K\3K\3L\6L\u01be\nL\rL\16L\u01bf\3M\6M\u01c3\nM\rM\16M\u01c4\3"+
		"M\3M\6M\u01c9\nM\rM\16M\u01ca\3N\3N\7N\u01cf\nN\fN\16N\u01d2\13N\3N\3"+
		"N\3O\3O\7O\u01d8\nO\fO\16O\u01db\13O\3O\3O\3P\3P\7P\u01e1\nP\fP\16P\u01e4"+
		"\13P\3Q\6Q\u01e7\nQ\rQ\16Q\u01e8\3Q\3Q\3R\3R\3R\3R\7R\u01f1\nR\fR\16R"+
		"\u01f4\13R\3R\3R\3R\3R\3R\3S\3S\3S\3S\7S\u01ff\nS\fS\16S\u0202\13S\3S"+
		"\3S\5\u01d0\u01d9\u01f2\2T\3\3\5\4\7\5\t\6\13\7\r\b\17\t\21\n\23\13\25"+
		"\f\27\r\31\16\33\17\35\20\37\21!\22#\23%\24\'\25)\26+\27-\30/\31\61\32"+
		"\63\33\65\34\67\359\36;\37= ?!A\"C#E$G%I&K\'M(O)Q*S+U,W-Y.[/]\60_\61a"+
		"\62c\63e\64g\65i\66k\67m8o9q:s;u<w=y>{?}@\177A\u0081B\u0083C\u0085D\u0087"+
		"E\u0089F\u008bG\u008dH\u008fI\u0091J\u0093K\u0095L\u0097M\u0099N\u009b"+
		"O\u009dP\u009fQ\u00a1R\u00a3S\u00a5T\3\2\7\3\2\62;\4\2aac|\5\2\62;aac"+
		"|\5\2\13\f\16\17\"\"\4\2\f\f\17\17\2\u020e\2\3\3\2\2\2\2\5\3\2\2\2\2\7"+
		"\3\2\2\2\2\t\3\2\2\2\2\13\3\2\2\2\2\r\3\2\2\2\2\17\3\2\2\2\2\21\3\2\2"+
		"\2\2\23\3\2\2\2\2\25\3\2\2\2\2\27\3\2\2\2\2\31\3\2\2\2\2\33\3\2\2\2\2"+
		"\35\3\2\2\2\2\37\3\2\2\2\2!\3\2\2\2\2#\3\2\2\2\2%\3\2\2\2\2\'\3\2\2\2"+
		"\2)\3\2\2\2\2+\3\2\2\2\2-\3\2\2\2\2/\3\2\2\2\2\61\3\2\2\2\2\63\3\2\2\2"+
		"\2\65\3\2\2\2\2\67\3\2\2\2\29\3\2\2\2\2;\3\2\2\2\2=\3\2\2\2\2?\3\2\2\2"+
		"\2A\3\2\2\2\2C\3\2\2\2\2E\3\2\2\2\2G\3\2\2\2\2I\3\2\2\2\2K\3\2\2\2\2M"+
		"\3\2\2\2\2O\3\2\2\2\2Q\3\2\2\2\2S\3\2\2\2\2U\3\2\2\2\2W\3\2\2\2\2Y\3\2"+
		"\2\2\2[\3\2\2\2\2]\3\2\2\2\2_\3\2\2\2\2a\3\2\2\2\2c\3\2\2\2\2e\3\2\2\2"+
		"\2g\3\2\2\2\2i\3\2\2\2\2k\3\2\2\2\2m\3\2\2\2\2o\3\2\2\2\2q\3\2\2\2\2s"+
		"\3\2\2\2\2u\3\2\2\2\2w\3\2\2\2\2y\3\2\2\2\2{\3\2\2\2\2}\3\2\2\2\2\177"+
		"\3\2\2\2\2\u0081\3\2\2\2\2\u0083\3\2\2\2\2\u0085\3\2\2\2\2\u0087\3\2\2"+
		"\2\2\u0089\3\2\2\2\2\u008b\3\2\2\2\2\u008d\3\2\2\2\2\u008f\3\2\2\2\2\u0091"+
		"\3\2\2\2\2\u0093\3\2\2\2\2\u0095\3\2\2\2\2\u0097\3\2\2\2\2\u0099\3\2\2"+
		"\2\2\u009b\3\2\2\2\2\u009d\3\2\2\2\2\u009f\3\2\2\2\2\u00a1\3\2\2\2\2\u00a3"+
		"\3\2\2\2\2\u00a5\3\2\2\2\3\u00a7\3\2\2\2\5\u00ad\3\2\2\2\7\u00b2\3\2\2"+
		"\2\t\u00bc\3\2\2\2\13\u00c3\3\2\2\2\r\u00c6\3\2\2\2\17\u00cc\3\2\2\2\21"+
		"\u00d1\3\2\2\2\23\u00da\3\2\2\2\25\u00dd\3\2\2\2\27\u00e2\3\2\2\2\31\u00e6"+
		"\3\2\2\2\33\u00e9\3\2\2\2\35\u00ed\3\2\2\2\37\u00f4\3\2\2\2!\u00fa\3\2"+
		"\2\2#\u0101\3\2\2\2%\u0105\3\2\2\2\'\u0107\3\2\2\2)\u0109\3\2\2\2+\u010b"+
		"\3\2\2\2-\u010d\3\2\2\2/\u010f\3\2\2\2\61\u0111\3\2\2\2\63\u0113\3\2\2"+
		"\2\65\u0115\3\2\2\2\67\u0117\3\2\2\29\u011b\3\2\2\2;\u011d\3\2\2\2=\u0120"+
		"\3\2\2\2?\u0122\3\2\2\2A\u0124\3\2\2\2C\u0126\3\2\2\2E\u0128\3\2\2\2G"+
		"\u012a\3\2\2\2I\u012c\3\2\2\2K\u012e\3\2\2\2M\u0131\3\2\2\2O\u0134\3\2"+
		"\2\2Q\u0137\3\2\2\2S\u013a\3\2\2\2U\u013d\3\2\2\2W\u0140\3\2\2\2Y\u0143"+
		"\3\2\2\2[\u0146\3\2\2\2]\u0149\3\2\2\2_\u014b\3\2\2\2a\u014d\3\2\2\2c"+
		"\u014f\3\2\2\2e\u0151\3\2\2\2g\u0153\3\2\2\2i\u0155\3\2\2\2k\u0157\3\2"+
		"\2\2m\u0159\3\2\2\2o\u015c\3\2\2\2q\u015f\3\2\2\2s\u0162\3\2\2\2u\u0165"+
		"\3\2\2\2w\u0168\3\2\2\2y\u016b\3\2\2\2{\u016e\3\2\2\2}\u0171\3\2\2\2\177"+
		"\u0175\3\2\2\2\u0081\u0179\3\2\2\2\u0083\u017e\3\2\2\2\u0085\u0183\3\2"+
		"\2\2\u0087\u0188\3\2\2\2\u0089\u018e\3\2\2\2\u008b\u0192\3\2\2\2\u008d"+
		"\u0197\3\2\2\2\u008f\u019d\3\2\2\2\u0091\u01a4\3\2\2\2\u0093\u01b5\3\2"+
		"\2\2\u0095\u01b7\3\2\2\2\u0097\u01bd\3\2\2\2\u0099\u01c2\3\2\2\2\u009b"+
		"\u01cc\3\2\2\2\u009d\u01d5\3\2\2\2\u009f\u01de\3\2\2\2\u00a1\u01e6\3\2"+
		"\2\2\u00a3\u01ec\3\2\2\2\u00a5\u01fa\3\2\2\2\u00a7\u00a8\7e\2\2\u00a8"+
		"\u00a9\7n\2\2\u00a9\u00aa\7c\2\2\u00aa\u00ab\7u\2\2\u00ab\u00ac\7u\2\2"+
		"\u00ac\4\3\2\2\2\u00ad\u00ae\7g\2\2\u00ae\u00af\7p\2\2\u00af\u00b0\7w"+
		"\2\2\u00b0\u00b1\7o\2\2\u00b1\6\3\2\2\2\u00b2\u00b3\7k\2\2\u00b3\u00b4"+
		"\7p\2\2\u00b4\u00b5\7v\2\2\u00b5\u00b6\7g\2\2\u00b6\u00b7\7t\2\2\u00b7"+
		"\u00b8\7h\2\2\u00b8\u00b9\7c\2\2\u00b9\u00ba\7e\2\2\u00ba\u00bb\7g\2\2"+
		"\u00bb\b\3\2\2\2\u00bc\u00bd\7k\2\2\u00bd\u00be\7o\2\2\u00be\u00bf\7r"+
		"\2\2\u00bf\u00c0\7q\2\2\u00c0\u00c1\7t\2\2\u00c1\u00c2\7v\2\2\u00c2\n"+
		"\3\2\2\2\u00c3\u00c4\7c\2\2\u00c4\u00c5\7u\2\2\u00c5\f\3\2\2\2\u00c6\u00c7"+
		"\7d\2\2\u00c7\u00c8\7t\2\2\u00c8\u00c9\7g\2\2\u00c9\u00ca\7c\2\2\u00ca"+
		"\u00cb\7m\2\2\u00cb\16\3\2\2\2\u00cc\u00cd\7e\2\2\u00cd\u00ce\7c\2\2\u00ce"+
		"\u00cf\7u\2\2\u00cf\u00d0\7g\2\2\u00d0\20\3\2\2\2\u00d1\u00d2\7e\2\2\u00d2"+
		"\u00d3\7q\2\2\u00d3\u00d4\7p\2\2\u00d4\u00d5\7v\2\2\u00d5\u00d6\7k\2\2"+
		"\u00d6\u00d7\7p\2\2\u00d7\u00d8\7w\2\2\u00d8\u00d9\7g\2\2\u00d9\22\3\2"+
		"\2\2\u00da\u00db\7f\2\2\u00db\u00dc\7q\2\2\u00dc\24\3\2\2\2\u00dd\u00de"+
		"\7g\2\2\u00de\u00df\7n\2\2\u00df\u00e0\7u\2\2\u00e0\u00e1\7g\2\2\u00e1"+
		"\26\3\2\2\2\u00e2\u00e3\7h\2\2\u00e3\u00e4\7q\2\2\u00e4\u00e5\7t\2\2\u00e5"+
		"\30\3\2\2\2\u00e6\u00e7\7k\2\2\u00e7\u00e8\7h\2\2\u00e8\32\3\2\2\2\u00e9"+
		"\u00ea\7n\2\2\u00ea\u00eb\7g\2\2\u00eb\u00ec\7v\2\2\u00ec\34\3\2\2\2\u00ed"+
		"\u00ee\7t\2\2\u00ee\u00ef\7g\2\2\u00ef\u00f0\7v\2\2\u00f0\u00f1\7w\2\2"+
		"\u00f1\u00f2\7t\2\2\u00f2\u00f3\7p\2\2\u00f3\36\3\2\2\2\u00f4\u00f5\7"+
		"y\2\2\u00f5\u00f6\7j\2\2\u00f6\u00f7\7k\2\2\u00f7\u00f8\7n\2\2\u00f8\u00f9"+
		"\7g\2\2\u00f9 \3\2\2\2\u00fa\u00fb\7u\2\2\u00fb\u00fc\7y\2\2\u00fc\u00fd"+
		"\7k\2\2\u00fd\u00fe\7v\2\2\u00fe\u00ff\7e\2\2\u00ff\u0100\7j\2\2\u0100"+
		"\"\3\2\2\2\u0101\u0102\7x\2\2\u0102\u0103\7c\2\2\u0103\u0104\7t\2\2\u0104"+
		"$\3\2\2\2\u0105\u0106\7*\2\2\u0106&\3\2\2\2\u0107\u0108\7+\2\2\u0108("+
		"\3\2\2\2\u0109\u010a\7}\2\2\u010a*\3\2\2\2\u010b\u010c\7\177\2\2\u010c"+
		",\3\2\2\2\u010d\u010e\7]\2\2\u010e.\3\2\2\2\u010f\u0110\7_\2\2\u0110\60"+
		"\3\2\2\2\u0111\u0112\7=\2\2\u0112\62\3\2\2\2\u0113\u0114\7.\2\2\u0114"+
		"\64\3\2\2\2\u0115\u0116\7\60\2\2\u0116\66\3\2\2\2\u0117\u0118\7\60\2\2"+
		"\u0118\u0119\7\60\2\2\u0119\u011a\7\60\2\2\u011a8\3\2\2\2\u011b\u011c"+
		"\7B\2\2\u011c:\3\2\2\2\u011d\u011e\7<\2\2\u011e\u011f\7<\2\2\u011f<\3"+
		"\2\2\2\u0120\u0121\7?\2\2\u0121>\3\2\2\2\u0122\u0123\7@\2\2\u0123@\3\2"+
		"\2\2\u0124\u0125\7>\2\2\u0125B\3\2\2\2\u0126\u0127\7#\2\2\u0127D\3\2\2"+
		"\2\u0128\u0129\7\u0080\2\2\u0129F\3\2\2\2\u012a\u012b\7A\2\2\u012bH\3"+
		"\2\2\2\u012c\u012d\7<\2\2\u012dJ\3\2\2\2\u012e\u012f\7/\2\2\u012f\u0130"+
		"\7@\2\2\u0130L\3\2\2\2\u0131\u0132\7?\2\2\u0132\u0133\7?\2\2\u0133N\3"+
		"\2\2\2\u0134\u0135\7>\2\2\u0135\u0136\7?\2\2\u0136P\3\2\2\2\u0137\u0138"+
		"\7@\2\2\u0138\u0139\7?\2\2\u0139R\3\2\2\2\u013a\u013b\7#\2\2\u013b\u013c"+
		"\7?\2\2\u013cT\3\2\2\2\u013d\u013e\7(\2\2\u013e\u013f\7(\2\2\u013fV\3"+
		"\2\2\2\u0140\u0141\7~\2\2\u0141\u0142\7~\2\2\u0142X\3\2\2\2\u0143\u0144"+
		"\7-\2\2\u0144\u0145\7-\2\2\u0145Z\3\2\2\2\u0146\u0147\7/\2\2\u0147\u0148"+
		"\7/\2\2\u0148\\\3\2\2\2\u0149\u014a\7-\2\2\u014a^\3\2\2\2\u014b\u014c"+
		"\7/\2\2\u014c`\3\2\2\2\u014d\u014e\7,\2\2\u014eb\3\2\2\2\u014f\u0150\7"+
		"\61\2\2\u0150d\3\2\2\2\u0151\u0152\7(\2\2\u0152f\3\2\2\2\u0153\u0154\7"+
		"~\2\2\u0154h\3\2\2\2\u0155\u0156\7`\2\2\u0156j\3\2\2\2\u0157\u0158\7\'"+
		"\2\2\u0158l\3\2\2\2\u0159\u015a\7-\2\2\u015a\u015b\7?\2\2\u015bn\3\2\2"+
		"\2\u015c\u015d\7/\2\2\u015d\u015e\7?\2\2\u015ep\3\2\2\2\u015f\u0160\7"+
		",\2\2\u0160\u0161\7?\2\2\u0161r\3\2\2\2\u0162\u0163\7\61\2\2\u0163\u0164"+
		"\7?\2\2\u0164t\3\2\2\2\u0165\u0166\7(\2\2\u0166\u0167\7?\2\2\u0167v\3"+
		"\2\2\2\u0168\u0169\7~\2\2\u0169\u016a\7?\2\2\u016ax\3\2\2\2\u016b\u016c"+
		"\7`\2\2\u016c\u016d\7?\2\2\u016dz\3\2\2\2\u016e\u016f\7\'\2\2\u016f\u0170"+
		"\7?\2\2\u0170|\3\2\2\2\u0171\u0172\7>\2\2\u0172\u0173\7>\2\2\u0173\u0174"+
		"\7?\2\2\u0174~\3\2\2\2\u0175\u0176\7@\2\2\u0176\u0177\7@\2\2\u0177\u0178"+
		"\7?\2\2\u0178\u0080\3\2\2\2\u0179\u017a\7@\2\2\u017a\u017b\7@\2\2\u017b"+
		"\u017c\7@\2\2\u017c\u017d\7?\2\2\u017d\u0082\3\2\2\2\u017e\u017f\7e\2"+
		"\2\u017f\u0180\7j\2\2\u0180\u0181\7c\2\2\u0181\u0182\7t\2\2\u0182\u0084"+
		"\3\2\2\2\u0183\u0184\7d\2\2\u0184\u0185\7{\2\2\u0185\u0186\7v\2\2\u0186"+
		"\u0187\7g\2\2\u0187\u0086\3\2\2\2\u0188\u0189\7u\2\2\u0189\u018a\7j\2"+
		"\2\u018a\u018b\7q\2\2\u018b\u018c\7t\2\2\u018c\u018d\7v\2\2\u018d\u0088"+
		"\3\2\2\2\u018e\u018f\7k\2\2\u018f\u0190\7p\2\2\u0190\u0191\7v\2\2\u0191"+
		"\u008a\3\2\2\2\u0192\u0193\7n\2\2\u0193\u0194\7q\2\2\u0194\u0195\7p\2"+
		"\2\u0195\u0196\7i\2\2\u0196\u008c\3\2\2\2\u0197\u0198\7h\2\2\u0198\u0199"+
		"\7n\2\2\u0199\u019a\7q\2\2\u019a\u019b\7c\2\2\u019b\u019c\7v\2\2\u019c"+
		"\u008e\3\2\2\2\u019d\u019e\7f\2\2\u019e\u019f\7q\2\2\u019f\u01a0\7w\2"+
		"\2\u01a0\u01a1\7d\2\2\u01a1\u01a2\7n\2\2\u01a2\u01a3\7g\2\2\u01a3\u0090"+
		"\3\2\2\2\u01a4\u01a5\7d\2\2\u01a5\u01a6\7q\2\2\u01a6\u01a7\7q\2\2\u01a7"+
		"\u01a8\7n\2\2\u01a8\u01a9\7g\2\2\u01a9\u01aa\7c\2\2\u01aa\u01ab\7p\2\2"+
		"\u01ab\u0092\3\2\2\2\u01ac\u01ad\7v\2\2\u01ad\u01ae\7t\2\2\u01ae\u01af"+
		"\7w\2\2\u01af\u01b6\7g\2\2\u01b0\u01b1\7h\2\2\u01b1\u01b2\7c\2\2\u01b2"+
		"\u01b3\7n\2\2\u01b3\u01b4\7u\2\2\u01b4\u01b6\7g\2\2\u01b5\u01ac\3\2\2"+
		"\2\u01b5\u01b0\3\2\2\2\u01b6\u0094\3\2\2\2\u01b7\u01b8\7p\2\2\u01b8\u01b9"+
		"\7w\2\2\u01b9\u01ba\7n\2\2\u01ba\u01bb\7n\2\2\u01bb\u0096\3\2\2\2\u01bc"+
		"\u01be\t\2\2\2\u01bd\u01bc\3\2\2\2\u01be\u01bf\3\2\2\2\u01bf\u01bd\3\2"+
		"\2\2\u01bf\u01c0\3\2\2\2\u01c0\u0098\3\2\2\2\u01c1\u01c3\t\2\2\2\u01c2"+
		"\u01c1\3\2\2\2\u01c3\u01c4\3\2\2\2\u01c4\u01c2\3\2\2\2\u01c4\u01c5\3\2"+
		"\2\2\u01c5\u01c6\3\2\2\2\u01c6\u01c8\7\60\2\2\u01c7\u01c9\t\2\2\2\u01c8"+
		"\u01c7\3\2\2\2\u01c9\u01ca\3\2\2\2\u01ca\u01c8\3\2\2\2\u01ca\u01cb\3\2"+
		"\2\2\u01cb\u009a\3\2\2\2\u01cc\u01d0\7)\2\2\u01cd\u01cf\13\2\2\2\u01ce"+
		"\u01cd\3\2\2\2\u01cf\u01d2\3\2\2\2\u01d0\u01d1\3\2\2\2\u01d0\u01ce\3\2"+
		"\2\2\u01d1\u01d3\3\2\2\2\u01d2\u01d0\3\2\2\2\u01d3\u01d4\7)\2\2\u01d4"+
		"\u009c\3\2\2\2\u01d5\u01d9\7$\2\2\u01d6\u01d8\13\2\2\2\u01d7\u01d6\3\2"+
		"\2\2\u01d8\u01db\3\2\2\2\u01d9\u01da\3\2\2\2\u01d9\u01d7\3\2\2\2\u01da"+
		"\u01dc\3\2\2\2\u01db\u01d9\3\2\2\2\u01dc\u01dd\7$\2\2\u01dd\u009e\3\2"+
		"\2\2\u01de\u01e2\t\3\2\2\u01df\u01e1\t\4\2\2\u01e0\u01df\3\2\2\2\u01e1"+
		"\u01e4\3\2\2\2\u01e2\u01e0\3\2\2\2\u01e2\u01e3\3\2\2\2\u01e3\u00a0\3\2"+
		"\2\2\u01e4\u01e2\3\2\2\2\u01e5\u01e7\t\5\2\2\u01e6\u01e5\3\2\2\2\u01e7"+
		"\u01e8\3\2\2\2\u01e8\u01e6\3\2\2\2\u01e8\u01e9\3\2\2\2\u01e9\u01ea\3\2"+
		"\2\2\u01ea\u01eb\bQ\2\2\u01eb\u00a2\3\2\2\2\u01ec\u01ed\7\61\2\2\u01ed"+
		"\u01ee\7,\2\2\u01ee\u01f2\3\2\2\2\u01ef\u01f1\13\2\2\2\u01f0\u01ef\3\2"+
		"\2\2\u01f1\u01f4\3\2\2\2\u01f2\u01f3\3\2\2\2\u01f2\u01f0\3\2\2\2\u01f3"+
		"\u01f5\3\2\2\2\u01f4\u01f2\3\2\2\2\u01f5\u01f6\7,\2\2\u01f6\u01f7\7\61"+
		"\2\2\u01f7\u01f8\3\2\2\2\u01f8\u01f9\bR\3\2\u01f9\u00a4\3\2\2\2\u01fa"+
		"\u01fb\7\61\2\2\u01fb\u01fc\7\61\2\2\u01fc\u0200\3\2\2\2\u01fd\u01ff\n"+
		"\6\2\2\u01fe\u01fd\3\2\2\2\u01ff\u0202\3\2\2\2\u0200\u01fe\3\2\2\2\u0200"+
		"\u0201\3\2\2\2\u0201\u0203\3\2\2\2\u0202\u0200\3\2\2\2\u0203\u0204\bS"+
		"\3\2\u0204\u00a6\3\2\2\2\r\2\u01b5\u01bf\u01c4\u01ca\u01d0\u01d9\u01e2"+
		"\u01e8\u01f2\u0200\4\b\2\2\2\3\2";
	public static final ATN _ATN =
		new ATNDeserializer().deserialize(_serializedATN.toCharArray());
	static {
		_decisionToDFA = new DFA[_ATN.getNumberOfDecisions()];
		for (int i = 0; i < _ATN.getNumberOfDecisions(); i++) {
			_decisionToDFA[i] = new DFA(_ATN.getDecisionState(i), i);
		}
	}
}