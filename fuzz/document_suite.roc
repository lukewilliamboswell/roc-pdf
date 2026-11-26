app [target] {
	deflate: "https://github.com/lukewilliamboswell/roc-deflate/releases/download/0.4.0-rc4/FoGWbhCP9K1Qk7HA9wcSxHYTpiwTHmCpfNUZx7rAGSSk.tar.zst",
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.8.0/BUNcJDHxCd7xLVSe3WBioyXqR6tm1MqXwzwGgtnmqK43.tar.zst",
	pdf: "../package/all.roc",
}

import fuzz.Fuzz
import JpegInspectorMutation
import AssociatedFilesProperty
import WidgetFormsProperty
import CheckboxFormsProperty
import FacadeOutputEquivalence
import FacadeStructure
import NavigationProperty
import RegistryProperty
import ThemeOptions

# roc test also runs the bounded models and proofs in this suite.
import AppearanceTransparencyModel
import AssociatedFilesModel
import FormAmbientTransparencyModel
import ContentScopeModel
import ColumnFlowModel
import GraphicsTransformModel
import ContinuationPaginationModel
import DenseSpanProof
import DocumentBuilderModel
import FixedPageOrderModel
import WidgetFormsModel
import GroupingContainmentModel
import HeadingFamilyModel
import InterLatinModel
import InternationalLineModel
import LinkRegionModel
import OutlineModel
import PageBreakModel
import PageLabelModel
import PageTreeProof
import PageViewport
import ReferenceWrapModel
import ResourceGraphModel
import StreamSealModel
import TaggedStreamOwners
import TableHeaderModel
import XrefSlotProof

target = Fuzz.suite([
	JpegInspectorMutation.target,
	AssociatedFilesProperty.target,
	WidgetFormsProperty.target,
	CheckboxFormsProperty.target,
	FacadeOutputEquivalence.target,
	FacadeStructure.target,
	NavigationProperty.target,
	RegistryProperty.target,
	ThemeOptions.target,
])
